import Foundation

@MainActor
@Observable
final class ViewerStore {
    private(set) var content: String = ""
    private(set) var fileType: FileType = .mmd
    private(set) var isDeleted: Bool = false
    private(set) var filePath: URL?

    private var fileWatcher: FileWatcher?

    func openFile(_ url: URL) {
        fileWatcher?.stop()
        filePath = url
        fileType = FileType(url: url)
        loadContent()

        fileWatcher = FileWatcher(path: url) { [weak self] in
            self?.loadContent()
        }
    }

    private func loadContent() {
        guard let filePath else { return }
        let resolved = filePath.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolved.path) {
            content = (try? String(contentsOf: resolved, encoding: .utf8)) ?? ""
            isDeleted = false
        } else {
            isDeleted = true
        }
    }

    func close() {
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
