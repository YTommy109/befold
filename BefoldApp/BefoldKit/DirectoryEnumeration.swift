import Foundation

/// ディレクトリ列挙・分類・ソートと「先頭の対応ファイル」判定の単一の実装元。
///
/// GUI サイドバー(`DirectoryLister`)と CLI/オープン経路(`SupportedFileResolver`)が
/// それぞれ FileManager を直接叩くと、隠しファイルの扱い・ソート順・
/// 「フォルダを開いたとき最初に開くファイル」の判定がドリフトする。
/// 列挙まわりはここに集約し、双方はここへ委譲すること。
public enum DirectoryEnumeration {
    /// ディレクトリ直下のエントリを列挙し、フォルダーとファイルに分類して
    /// それぞれファイル名の localizedStandardCompare 昇順で返す。
    /// 実体が存在しないダングリングシンボリックリンク等の非通常エントリも files に算入する
    /// (サイレントに一覧から消さず、開こうとした時点で既存のオープン/エラー表示フローに委譲する)。
    /// 列挙に失敗した場合は空の組を返す。
    public static func sortedContents(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> (folders: [URL], files: [URL]) {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: options
        ) else {
            return ([], [])
        }

        var folders: [URL] = []
        var files: [URL] = []
        // 列挙の出口で裏打ちを揃える。FileManager が返す URL は NSString 裏打ちで、
        // SwiftUI の行 ID やパスの辞書キーとしてハッシュされるたびに 1 文字ずつの
        // Unicode 正規化が走る。ここが URL がアプリへ入る境界なので、消費側
        // (サイドバー一覧・Quick Open の候補)ごとに揃え直す必要をなくす。
        for url in contents.map(\.nativeBackedFileURL) {
            if fileReader.isDirectory(at: url) {
                folders.append(url)
            } else {
                files.append(url)
            }
        }
        return (folders.sortedByFileName(), files.sortedByFileName())
    }

    /// ディレクトリ直下の非ディレクトリエントリを、ファイル名の自然順でソートして返す。
    public static func sortedFiles(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> [URL] {
        sortedContents(in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader).files
    }

    /// ディレクトリ直下の最初の対応形式(`FileType.isSupported`)ファイル。無ければ nil。
    public static func firstSupportedFile(
        in directory: URL,
        showHiddenFiles: Bool = false,
        fileReader: any FileReading
    ) -> URL? {
        sortedFiles(in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader).firstSupported()
    }

    /// 「フォルダを開いたとき最初に開くファイル」の選択規則の単一の実装元。
    /// 対応形式を優先し、無ければ先頭のファイルにフォールバックする。
    static func fileToOpen(from files: [URL]) -> URL? {
        files.firstSupported() ?? files.first
    }
}

extension [URL] {
    /// ファイル名(lastPathComponent)の localizedStandardCompare 昇順ソート。
    /// 列挙結果の並びを一箇所に固定するため、呼び出し側で個別に sorted を書かない。
    public func sortedByFileName() -> [URL] {
        sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    fileprivate func firstSupported() -> URL? {
        first(where: FileType.isSupported)
    }
}
