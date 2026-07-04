import Foundation
@testable import mmdview

/// メモリ上の辞書でファイルシステムを模す FileReading 実装。
/// キーは URL.path(テストではシンボリックリンクを含まないパスを使うこと)。
final class InMemoryFileReader: FileReading, Sendable {
    private let files: LockedBox<[String: String]>

    init(files: [String: String] = [:]) {
        self.files = LockedBox(files)
    }

    /// ファイルを作成/上書きする。nil を渡すと削除する。
    func setFile(_ contents: String?, at url: URL) {
        files.update { $0[url.path] = contents }
    }

    func fileExists(at url: URL) -> Bool {
        files.get()[url.path] != nil
    }

    func readString(from url: URL) throws -> String {
        guard let contents = files.get()[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return contents
    }
}
