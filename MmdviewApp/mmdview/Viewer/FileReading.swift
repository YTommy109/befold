import Foundation

/// ファイルの存在確認と内容読み込みを抽象化する(テストでの差し替え用)。
protocol FileReading: Sendable {
    func fileExists(at url: URL) -> Bool
    func readString(from url: URL) throws -> String
}

/// FileManager / String(contentsOf:) による標準実装。
struct DefaultFileReader: FileReading {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readString(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
