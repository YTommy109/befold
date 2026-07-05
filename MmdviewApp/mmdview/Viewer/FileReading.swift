import Foundation

/// ファイルの存在確認と内容読み込みを抽象化する(テストでの差し替え用)。
protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
    /// 先頭数KBにNULバイトが含まれるかでバイナリかどうかを判定する。
    func isBinary(at url: URL) -> Bool
}

/// FileManager / String(contentsOf:) による標準実装。
struct DefaultFileReader: FileReading {
    /// バイナリ判定に読む先頭バイト数。
    private static let binarySniffLength = 8192

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readString(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// 先頭 8KB を読み、NULバイト(0x00)が1つでも含まれればバイナリと判定する。
    /// ファイルを開けない場合はテキスト扱い(false)とし、readString 側の
    /// エラー処理に委ねる。
    func isBinary(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.binarySniffLength) else { return false }
        return data.contains(0)
    }
}
