import Foundation

/// GUI・CLI 双方の「開く対象パス」解決の単一の実装元。
public enum SupportedFileResolver {
    /// 指定 URL がディレクトリなら、対応形式(FileType.isSupported)を優先してその中の
    /// 1ファイルを返す。対応形式が無ければ最初のファイルを返す(ファイルが1つもなければ nil)。
    /// ファイル・存在しないパスはそのまま返す(既存のオープン/エラー表示フローに委譲する)。
    public static func resolveFileToOpen(at url: URL, fileReader: any FileReading) -> URL? {
        guard fileReader.isDirectory(at: url) else { return url }
        let files = sortedFiles(in: url, fileReader: fileReader)
        return files.first(where: FileType.isSupported) ?? files.first
    }

    /// ディレクトリ直下の非ディレクトリエントリを、ファイル名の自然順でソートして返す。
    /// 実体が存在しないダングリングシンボリックリンク等の非通常エントリも含める
    /// (サイレントに一覧から消さず、開こうとした時点で既存のオープン/エラー表示フローに委譲する)。
    private static func sortedFiles(in directory: URL, fileReader: any FileReading) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { !fileReader.isDirectory(at: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
