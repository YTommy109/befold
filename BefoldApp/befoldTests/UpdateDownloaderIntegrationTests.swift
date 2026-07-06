@testable import befold
import Foundation
import Testing

/// HTTP エラー応答を再現する URLProtocol スタブ。
/// 状態を持たず scheme で判定するため、他テストの file:// ダウンロードには干渉しない。
private final class HTTP404URLProtocol: URLProtocol {
    // URLProtocol の class func オーバーライドは static に変更できない
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 404, httpVersion: nil, headerFields: nil
              )
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
    @Test
    func downloadsFileAndReportsCompletion() async throws {
        let tmp = try TempDir(prefix: "befold-download-test")
        defer { withExtendedLifetime(tmp) {} }
        let source = tmp.url.appendingPathComponent("source.bin")
        let content = Data((0 ..< 200_000).map { UInt8($0 % 256) })
        try content.write(to: source)
        let destination = tmp.url.appendingPathComponent("dest.bin")

        let progress = LockedBox<[Double]>([])
        try await UpdateDownloader().download(from: source, to: destination) { value in
            progress.update { $0.append(value) }
        }

        #expect(try Data(contentsOf: destination) == content)
        #expect(progress.get().last == 1.0)
    }

    @Test
    func overwritesExistingDestination() async throws {
        let tmp = try TempDir(prefix: "befold-download-test")
        defer { withExtendedLifetime(tmp) {} }
        let source = tmp.url.appendingPathComponent("source.bin")
        try Data("new".utf8).write(to: source)
        let destination = tmp.url.appendingPathComponent("dest.bin")
        try Data("old-longer-content".utf8).write(to: destination)

        try await UpdateDownloader().download(from: source, to: destination) { _ in }

        #expect(try Data(contentsOf: destination) == Data("new".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func httpErrorStatusThrows() async throws {
        // https スキームのみを乗っ取るスタブを登録し、404 応答を返させる
        URLProtocol.registerClass(HTTP404URLProtocol.self)
        defer { URLProtocol.unregisterClass(HTTP404URLProtocol.self) }
        let tmp = try TempDir(prefix: "befold-download-test")
        defer { withExtendedLifetime(tmp) {} }
        let destination = tmp.url.appendingPathComponent("dest.bin")
        let url = try #require(URL(string: "https://example.com/befold.dmg"))

        await #expect(throws: (any Error).self) {
            try await UpdateDownloader().download(from: url, to: destination) { _ in }
        }
    }
}
