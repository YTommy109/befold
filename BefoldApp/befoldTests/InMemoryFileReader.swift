@testable import befold
import BefoldKit
import Foundation

/// メモリ上の辞書でファイルシステムを模す FileReading 実装。
/// キーは URL.path(テストではシンボリックリンクを含まないパスを使うこと)。
/// テキストもバイナリも単一の Data ストアで管理する。
final class InMemoryFileReader: FileReading, Sendable {
    private let files: LockedBox<[String: Data]>
    private let binaryPaths: LockedBox<Set<String>>
    private let readErrorPaths: LockedBox<Set<String>>
    private let sizeOverrides: LockedBox<[String: Int]>

    init(files: [String: String] = [:]) {
        self.files = LockedBox(files.mapValues { Data($0.utf8) })
        binaryPaths = LockedBox([])
        readErrorPaths = LockedBox([])
        sizeOverrides = LockedBox([:])
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
        files.get()[url.path] != nil
    }

    func readString(from url: URL) throws -> String {
        try String(decoding: readData(from: url), as: UTF8.self)
    }

    func readString(from url: URL, maxBytes: Int) throws -> String {
        let full = try readString(from: url)
        let data = Data(full.utf8)
        if data.count <= maxBytes { return full }
        let prefix = data.prefix(maxBytes)
        if let lastNewline = prefix.lastIndex(of: UInt8(ascii: "\n")) {
            return String(decoding: prefix[prefix.startIndex ... lastNewline], as: UTF8.self)
        }
        return String(decoding: prefix, as: UTF8.self)
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

    func fileSize(at url: URL) -> Int? {
        if nullSizePaths.get().contains(url.path) { return nil }
        if let override = sizeOverrides.get()[url.path] { return override }
        return files.get()[url.path]?.count
    }
}
