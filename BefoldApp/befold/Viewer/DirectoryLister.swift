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

    static func listEntries(in directory: URL, sortOrder: SortOrder) -> [FileListEntry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let supportedExtensions = FileType.allExtensions
        var folders: [URL] = []
        var files: [URL] = []

        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                folders.append(url)
            } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }

        let nameSort: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        folders.sort(by: nameSort)
        files.sort(by: nameSort)

        var entries: [FileListEntry] = []

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let dir = directory.standardizedFileURL
        if dir != home {
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
}
