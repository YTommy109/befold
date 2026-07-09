import Foundation

enum DirectoryLister {
    static func listFiles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return !isDirectory
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func listEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) -> [FileListEntry] {
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            return []
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

        let nameSort: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        folders.sort(by: nameSort)
        files.sort(by: nameSort)

        var entries: [FileListEntry] = []

        let parent = directory.deletingLastPathComponent().standardizedFileURL
        if isWithinHome(parent) {
            entries.append(FileListEntry(url: directory.deletingLastPathComponent(), kind: .parentNavigation))
        }

        switch sortOrder {
        case .foldersFirst:
            entries += folders.map { FileListEntry(url: $0, kind: .folder) }
            entries += files.map { FileListEntry(url: $0, kind: .file) }
        case .alphabetical:
            var mixed = folders.map { FileListEntry(url: $0, kind: .folder) }
                + files.map { FileListEntry(url: $0, kind: .file) }
            mixed.sort(by: { nameSort($0.url, $1.url) })
            entries += mixed
        }

        return entries
    }

    static func containsSupportedFile(in directory: URL) -> Bool {
        firstSupportedFile(in: directory) != nil
    }

    static func firstSupportedFile(in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents
            .filter { url in
                let isDir = (try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ))?.isDirectory ?? false
                return !isDir && FileType.isSupported(url)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare(
                    $1.lastPathComponent
                ) == .orderedAscending
            }
            .first
    }

    /// 指定 URL がホームディレクトリ自身、またはその配下かどうかを判定する。
    /// 前方一致だけの兄弟パス(例: ホームが `/Users/xxx` のとき `/Users/xxx2`)を
    /// 誤って含めないよう、区切り文字 `/` を含めて比較する。
    static func isWithinHome(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let target = url.standardizedFileURL
        return target == home || target.path.hasPrefix(home.path + "/")
    }

    /// 指定パスが存在するディレクトリかどうかを判定する。
    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
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
}
