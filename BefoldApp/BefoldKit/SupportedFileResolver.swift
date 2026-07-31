import Foundation

/// GUI・CLI 双方の「開く対象パス」解決の単一の実装元。
public enum SupportedFileResolver {
    /// 指定 URL がディレクトリなら、対応形式(FileType.isSupported)を優先してその中の
    /// 1ファイルを返す。対応形式が無ければ最初のファイルを返す(ファイルが1つもなければ nil)。
    /// ファイル・存在しないパスはそのまま返す(既存のオープン/エラー表示フローに委譲する)。
    /// 列挙・ソート・選択規則は DirectoryEnumeration(単一の実装元)に委譲する。
    public static func resolveFileToOpen(at url: URL, fileReader: any FileReading) -> URL? {
        guard fileReader.isDirectory(at: url) else { return url }
        let files = DirectoryEnumeration.sortedFiles(in: url, fileReader: fileReader)
        return DirectoryEnumeration.fileToOpen(from: files)
    }
}
