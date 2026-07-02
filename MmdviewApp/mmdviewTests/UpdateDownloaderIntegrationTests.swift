import Foundation
import Testing
@testable import mmdview

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var last: Double? { lock.withLock { values.last } }
    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }
}

/// HTTP エラー応答を再現する URLProtocol スタブ。
/// 状態を持たず scheme で判定するため、他テストの file:// ダウンロードには干渉しない。
private final class HTTP404URLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite
struct UpdateDownloaderIntegrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-download-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test
    func downloadsFileAndReportsCompletion() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.bin")
        let content = Data((0..<200_000).map { UInt8($0 % 256) })
        try content.write(to: source)
        let destination = dir.appendingPathComponent("dest.bin")

        let recorder = ProgressRecorder()
        try await UpdateDownloader().download(from: source, to: destination) { value in
            recorder.record(value)
        }

        #expect(try Data(contentsOf: destination) == content)
        #expect(recorder.last == 1.0)
    }

    @Test
    func overwritesExistingDestination() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.bin")
        try Data("new".utf8).write(to: source)
        let destination = dir.appendingPathComponent("dest.bin")
        try Data("old-longer-content".utf8).write(to: destination)

        try await UpdateDownloader().download(from: source, to: destination) { _ in }

        #expect(try Data(contentsOf: destination) == Data("new".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func httpErrorStatusThrows() async throws {
        // https スキームのみを乗っ取るスタブを登録し、404 応答を返させる
        URLProtocol.registerClass(HTTP404URLProtocol.self)
        defer { URLProtocol.unregisterClass(HTTP404URLProtocol.self) }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("dest.bin")
        let url = try #require(URL(string: "https://example.com/mmdview.dmg"))

        await #expect(throws: (any Error).self) {
            try await UpdateDownloader().download(from: url, to: destination) { _ in }
        }
    }
}
