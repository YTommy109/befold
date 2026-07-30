@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation

/// メモリ上の辞書でファイルシステムを模す FileReading 実装。
/// キーは URL.path(テストではシンボリックリンクを含まないパスを使うこと)。
/// テキストもバイナリも単一の Data ストアで管理する。
final class InMemoryFileReader: FileReading, Sendable {
    private let files: LockedBox<[String: Data]>
    private let directories: LockedBox<Set<String>>
    private let binaryPaths: LockedBox<Set<String>>
    private let readErrorPaths: LockedBox<Set<String>>
    private let sizeOverrides: LockedBox<[String: Int]>
    private let modificationDates: LockedBox<[String: Date]>

    /// - Parameter directories: 存在するディレクトリとして扱う URL.path の集合。
    ///   省略時は空集合(=ディレクトリを持たない、従来どおりの挙動)で、既存の呼び出し元は変更不要。
    init(files: [String: String] = [:], directories: Set<String> = []) {
        self.files = LockedBox(files.mapValues { Data($0.utf8) })
        self.directories = LockedBox(directories)
        binaryPaths = LockedBox([])
        readErrorPaths = LockedBox([])
        sizeOverrides = LockedBox([:])
        modificationDates = LockedBox([:])
    }

    /// テキストファイルを作成/上書きする。nil を渡すと削除する。
    func setFile(_ contents: String?, at url: URL) {
        files.update { $0[url.path] = contents.map { Data($0.utf8) } }
    }

    /// バイナリファイルを作成/上書きする。nil を渡すと削除する。
    func setDataFile(_ data: Data?, at url: URL) {
        files.update { $0[url.path] = data }
    }

    /// このパスをバイナリファイルとしてマークする(isBinary(at:) が true を返すようになる)。
    func setBinary(_ isBinary: Bool, at url: URL) {
        binaryPaths.update { paths in
            if isBinary {
                paths.insert(url.path)
            } else {
                paths.remove(url.path)
            }
        }
    }

    /// このパスの読み込みを失敗させる(存在はするが readString / readData が throw する)。
    func setReadError(_ fails: Bool, at url: URL) {
        readErrorPaths.update { paths in
            if fails {
                paths.insert(url.path)
            } else {
                paths.remove(url.path)
            }
        }
    }

    /// このパスの報告サイズ(バイト)を上書きする。nil で上書きを解除する
    /// (未設定なら内容のバイト数を返す)。
    func setSize(_ size: Int?, at url: URL) {
        sizeOverrides.update { $0[url.path] = size }
    }

    func fileExists(at url: URL) -> Bool {
        files.get()[url.path] != nil || directories.get().contains(url.path)
    }

    /// init の directories に含まれるパスのみ true。未指定なら常に false(従来どおり)。
    func isDirectory(at url: URL) -> Bool {
        directories.get().contains(url.path)
    }

    /// 存在し、かつディレクトリでないパスのみ true。
    func isExistingFile(at url: URL) -> Bool {
        fileExists(at: url) && !isDirectory(at: url)
    }

    func readString(from url: URL) throws -> String {
        try String(decoding: readData(from: url), as: UTF8.self)
    }

    func readData(from url: URL) throws -> Data {
        guard !readErrorPaths.get().contains(url.path) else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let data = files.get()[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func isBinary(at url: URL) -> Bool {
        binaryPaths.get().contains(url.path)
    }

    private let nullSizePaths: LockedBox<Set<String>> = LockedBox([])

    func setSizeUnknown(_ unknown: Bool, at url: URL) {
        nullSizePaths.update { paths in
            if unknown { paths.insert(url.path) } else { paths.remove(url.path) }
        }
    }

    /// このパスの最終更新日時を設定する。nil で解除する
    /// (未設定なら modificationDate(at:) は nil を返す)。
    func setModificationDate(_ date: Date?, at url: URL) {
        modificationDates.update { $0[url.path] = date }
    }

    func modificationDate(at url: URL) -> Date? {
        modificationDates.get()[url.path]
    }

    func fileSize(at url: URL) -> Int? {
        if nullSizePaths.get().contains(url.path) { return nil }
        if let override = sizeOverrides.get()[url.path] { return override }
        return files.get()[url.path]?.count
    }
}
