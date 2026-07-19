import BefoldKit
import Foundation

enum DirectoryLister {
    /// 存在確認・ディレクトリ判定の単一の実装元。ObjCBool の取り回しは
    /// DefaultFileReader に集約し、ここではそこへ委譲する。
    private static let fileReader: any FileReading = DefaultFileReader()

    static func listFiles(in directory: URL) -> [URL] {
        sortedContents(in: directory).files
    }

    static func listEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) -> [FileListEntry] {
        let (folders, files) = sortedContents(in: directory, showHiddenFiles: showHiddenFiles)

        var entries: [FileListEntry] = []

        let parent = directory.deletingLastPathComponent()
        if isWithinHome(parent) {
            entries.append(FileListEntry(url: parent, kind: .parentNavigation))
        }

        switch sortOrder {
        case .foldersFirst:
            entries += folders.map { FileListEntry(url: $0, kind: .folder) }
            entries += files.map { FileListEntry(url: $0, kind: .file) }
        case .alphabetical:
            var mixed = folders.map { FileListEntry(url: $0, kind: .folder) }
                + files.map { FileListEntry(url: $0, kind: .file) }
            mixed.sort {
                $0.url.lastPathComponent.localizedStandardCompare(
                    $1.url.lastPathComponent
                ) == .orderedAscending
            }
            entries += mixed
        }

        return entries
    }

    static func containsSupportedFile(in directory: URL) -> Bool {
        firstSupportedFile(in: directory) != nil
    }

    static func firstSupportedFile(in directory: URL) -> URL? {
        listFiles(in: directory).first(where: FileType.isSupported)
    }

    /// 指定 URL がホームディレクトリ自身、またはその配下かどうかを判定する。
    /// symlink を解決した normalizedPathKey で比較し、パス表記の揺れを吸収する。
    /// 前方一致だけの兄弟パス(例: ホームが `/Users/xxx` のとき `/Users/xxx2`)を
    /// 誤って含めないよう、区切り文字 `/` を含めて比較する。
    static func isWithinHome(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.normalizedPathKey
        let target = url.normalizedPathKey
        return target == home || target.hasPrefix(home + "/")
    }

    /// 指定パスが存在するファイル(ディレクトリでない)かどうかを判定する。
    static func isExistingFile(_ url: URL) -> Bool {
        fileReader.isExistingFile(at: url)
    }

    /// 指定パスが存在するかどうかを判定する(ディレクトリ含む)。
    static func fileExists(_ url: URL) -> Bool {
        fileReader.fileExists(at: url)
    }

    /// 指定パスが存在するディレクトリかどうかを判定する。
    static func isDirectory(_ url: URL) -> Bool {
        fileReader.isDirectory(at: url)
    }

    /// CLI シム経由のオープン用にパスを解決する。
    /// ディレクトリなら最初の対応ファイルを優先し、無ければ最初のファイルを返す
    /// (ファイルが1つもなければ nil)。ファイル・存在しないパスはそのまま返す
    /// (既存のオープン/エラー表示フローに委譲する)。
    static func resolveFileToOpen(at url: URL) -> URL? {
        guard isDirectory(url) else {
            return url
        }
        return firstSupportedFile(in: url) ?? listFiles(in: url).first
    }

    // MARK: - Private

    /// ディレクトリ内容を列挙し、フォルダーとファイルに分類してファイル名ソート済みで返す。
    private static func sortedContents(
        in directory: URL, showHiddenFiles: Bool = false
    ) -> (folders: [URL], files: [URL]) {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            return ([], [])
        }

        var folders: [URL] = []
        var files: [URL] = []

        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                folders.append(url)
            } else {
                files.append(url)
            }
        }

        return (folders.sortedByFileName(), files.sortedByFileName())
    }
}

private extension [URL] {
    func sortedByFileName() -> [URL] {
        sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
