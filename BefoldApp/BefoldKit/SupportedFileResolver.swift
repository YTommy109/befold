import Foundation

/// GUI・CLI 双方の「開く対象パス」解決の単一の実装元。
public enum SupportedFileResolver {
    /// 指定 URL がディレクトリなら、対応形式(FileType.isSupported)を優先してその中の
    /// 1ファイルを返す。対応形式が無ければ最初のファイルを返す(ファイルが1つもなければ nil)。
    /// ファイル・存在しないパスはそのまま返す(既存のオープン/エラー表示フローに委譲する)。
    /// 列挙・ソート・選択規則は DirectoryEnumeration(単一の実装元)に委譲する。
    ///
    /// **列挙失敗はここで nil へ畳む(空のフォルダと区別しない)。** 戻り値の消費側は
    /// 「開く対象が決まらなかった」ときに既存のエラー表示へ落ちる経路しか持たず、
    /// GUI(SessionRestorer / AppDelegate)も CLI(CLICheckCommand)も理由で分岐しない。
    /// 案内の文言を理由ごとに分けるかは別途決める(TASK-404 の申し送り)。
    public static func resolveFileToOpen(at url: URL, fileReader: any FileReading) -> URL? {
        guard fileReader.isDirectory(at: url) else { return url }
        guard let files = DirectoryEnumeration.sortedFiles(in: url, fileReader: fileReader) else {
            return nil
        }
        return DirectoryEnumeration.fileToOpen(from: files)
    }
}
