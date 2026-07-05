import Foundation

/// ビューアの表示状態を管理する。
/// ファイルの読み込み・監視・削除検知を行い、UI にバインドされるプロパティを更新する。
@MainActor
@Observable
final class ViewerStore {
    typealias WatcherFactory = @MainActor @Sendable (
        URL,
        @escaping @MainActor @Sendable () -> Void,
        (@MainActor @Sendable (URL) -> Void)?
    ) -> FileWatching

    private(set) var content: String = ""
    private(set) var fileType: FileType = .mmd
    private(set) var isDeleted: Bool = false
    /// 開いたファイルがバイナリなど非対応内容と判定された場合に true になる。
    /// true の間 content は更新されない(バイナリを丸ごと文字列化しない)。
    private(set) var isUnsupported: Bool = false
    private(set) var filePath: URL?

    /// 開いているファイルが rename / move されたときに新 URL を通知する。
    /// ウィンドウ側がタイトル・representedURL・セッション記録を更新するために使う。
    var onFileRenamed: ((URL) -> Void)?

    private var fileWatcher: FileWatching?
    private let makeWatcher: WatcherFactory
    private let fileReader: any FileReading

    init(watcherFactory: WatcherFactory? = nil, fileReader: any FileReading = DefaultFileReader()) {
        makeWatcher = watcherFactory ?? { url, onChange, onRename in
            FileWatcher(path: url, onChange: onChange, onRename: onRename)
        }
        self.fileReader = fileReader
    }

    /// 指定 URL のファイルを開き、ファイル監視を開始する。
    /// 既に別のファイルを開いている場合は、先に監視を停止してから切り替える。
    func openFile(_ url: URL) {
        fileWatcher?.stop()
        filePath = url
        fileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// filePath / fileType を新 URL に更新し、コンテンツを再読込したうえでウィンドウ側へ通知する。
    private func handleRename(to newURL: URL) {
        filePath = newURL
        fileType = FileType(url: newURL)
        loadContent()
        onFileRenamed?(newURL)
    }

    private func loadContent() {
        guard let filePath else { return }
        let resolved = filePath.resolvingSymlinksInPath()
        guard fileReader.fileExists(at: resolved) else {
            isDeleted = true
            isUnsupported = false
            return
        }
        isDeleted = false

        guard !fileReader.isBinary(at: resolved) else {
            isUnsupported = true
            content = ""
            return
        }
        isUnsupported = false
        content = (try? fileReader.readString(from: resolved)) ?? ""
    }

    /// ファイル監視を停止し、リソースを解放する。
    func close() {
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
