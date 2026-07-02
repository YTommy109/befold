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

struct UpdateDownloaderTests {
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
}
