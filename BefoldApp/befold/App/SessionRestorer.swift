import AppKit
import BefoldKit

/// 前回セッションのウィンドウ/タブ構成のスナップショットと復元を担う。
@MainActor
final class SessionRestorer {
    private let sessionStore: SessionStore
    private let windowManager: ViewerWindowManager
    private let fileReader: any FileReading
    /// 前回セッションで開いていたファイル。起動イベントで開かれるファイルの記録と混ざらないよう
    /// captureSavedState で読み取り、restoreLastSession で復元する。
    private var urlsToRestore: [URL] = []
    /// 前回終了時のタブ構成。urlsToRestore と同様に captureSavedState で先読みする。
    private var layoutToRestore: SessionLayout?
    /// 前回アクティブだったファイルの正規化パス。
    private var activePathToRestore: String?

    init(
        sessionStore: SessionStore,
        windowManager: ViewerWindowManager,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.sessionStore = sessionStore
        self.windowManager = windowManager
        self.fileReader = fileReader
    }

    /// 保存済みのセッション状態を先読みする。applicationWillFinishLaunching で呼ぶ。
    func captureSavedState() {
        urlsToRestore = sessionStore.savedURLs()
        layoutToRestore = sessionStore.savedLayout()
        activePathToRestore = sessionStore.savedActivePath()
    }

    /// 現在のウィンドウ/タブ構成をスナップショットする。
    /// NSApp.orderedWindows は前面から順に返るため、グループの並びも前面優先で保存される。
    func currentSessionLayout() -> SessionLayout {
        var groups: [SessionLayout.TabGroup] = []
        var seenWindows: Set<ObjectIdentifier> = []

        func appendGroup(for window: NSWindow) {
            guard !seenWindows.contains(ObjectIdentifier(window)),
                  windowManager.viewerPath(of: window) != nil else { return }

            let tabWindows = window.tabGroup?.windows ?? [window]
            for tabWindow in tabWindows {
                seenWindows.insert(ObjectIdentifier(tabWindow))
            }

            let paths = tabWindows.compactMap { windowManager.viewerPath(of: $0) }
            guard !paths.isEmpty else { return }
            let selectedWindow = window.tabGroup?.selectedWindow ?? window
            groups.append(
                SessionLayout.TabGroup(
                    paths: paths, selectedPath: windowManager.viewerPath(of: selectedWindow)
                )
            )
        }

        for window in NSApp.orderedWindows {
            appendGroup(for: window)
        }
        // orderedWindows は最小化(Dock 収納)・非表示のウィンドウを含まないため、
        // NSApp.windows で残りのビューアウィンドウのグループを末尾に補完する
        for window in NSApp.windows {
            appendGroup(for: window)
        }
        return SessionLayout(groups: groups)
    }

    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    /// SessionLayout があればタブグループ構成・タブ順・選択タブを再現し、無ければ従来どおり開いた順に開く。
    /// 最後に前回アクティブだったファイルをキーウィンドウにする。
    func restoreLastSession() {
        // 復元中のウィンドウ表示がシステムの「タブ優先」設定で勝手にタブ結合しないよう、
        // 自動タブ化を一時的に無効にする(グループ構成は addTabbedWindow で明示的に再現する)
        let allowsTabbing = NSWindow.allowsAutomaticWindowTabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        defer { NSWindow.allowsAutomaticWindowTabbing = allowsTabbing }

        let existingURLs = urlsToRestore.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue
            else {
                sessionStore.noteClosed(url)
                return false
            }
            return true
        }
        urlsToRestore = []

        let urlByPath = Dictionary(existingURLs.map { ($0.normalizedPathKey, $0) }) { first, _ in first }
        var restoredPaths: Set<String> = []

        if let layout = layoutToRestore?.filtered(to: Set(urlByPath.keys)) {
            for group in layout.groups {
                restoreTabGroup(group, urlByPath: urlByPath)
                restoredPaths.formUnion(group.paths)
            }
        }
        layoutToRestore = nil

        // レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く
        for url in existingURLs where !restoredPaths.contains(url.normalizedPathKey) {
            windowManager.openViewer(for: url)
        }

        // 前回アクティブだったファイルをキーウィンドウにする(開けていなければ成り行きのまま)
        if let activePath = activePathToRestore,
           let window = windowManager.window(forPath: activePath)
        {
            window.makeKeyAndOrderFront(nil)
        }
        activePathToRestore = nil
    }

    /// 1 つのタブグループを復元する。先頭のウィンドウに残りを順にタブ連結し、選択タブを再現する。
    private func restoreTabGroup(_ group: SessionLayout.TabGroup, urlByPath: [String: URL]) {
        var previousWindow: NSWindow?
        for path in group.paths {
            guard let url = urlByPath[path] else { continue }
            windowManager.openViewer(for: url)
            guard let window = windowManager.window(forPath: path) else { continue }
            // システムの「書類を開くときはタブで開く」設定に依存しないよう明示的にタブ化する
            previousWindow?.addTabbedWindow(window, ordered: .above)
            previousWindow = window
        }
        if let selectedPath = group.selectedPath,
           let selectedWindow = windowManager.window(forPath: selectedPath)
        {
            selectedWindow.tabGroup?.selectedWindow = selectedWindow
        }
    }
}
