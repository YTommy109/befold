import Foundation
@testable import mmdview

/// メモリ上の辞書でファイルシステムを模す FileReading 実装。
/// キーは URL.path(テストではシンボリックリンクを含まないパスを使うこと)。
final class InMemoryFileReader: FileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String]

    init(files: [String: String] = [:]) {
        self.files = files
    }

    /// ファイルを作成/上書きする。nil を渡すと削除する。
    func setFile(_ contents: String?, at url: URL) {
        lock.withLock { files[url.path] = contents }
    }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { files[url.path] != nil }
    }

    func readString(from url: URL) throws -> String {
        try lock.withLock {
            guard let contents = files[url.path] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return contents
        }
    }
}
