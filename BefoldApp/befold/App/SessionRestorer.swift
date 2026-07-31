import AppKit
import BefoldCLI
import BefoldKit

/// 前回セッションのウィンドウ/タブ構成のスナップショットと復元を担う。
@MainActor
final class SessionRestorer {
    private let sessionStore: SessionStore
    private let windowManager: ViewerWindowManager
    private let fileReader: any FileReading
    /// openRootFallback の解決シーム。既定は DirectoryLister.resolveFileToOpen(実 FileManager でのディレクトリ
    /// 列挙)だが、テストでは仮想パスを実 FS 抜きで解決したスタブに差し替えられるようにする
    /// (DirectoryLister.resolveFileToOpen は内部でディレクトリ列挙に実 FileManager を使うため、
    /// InMemoryFileReader だけの仮想パスでは検証できない)。
    private let resolveFileToOpen: (URL) -> URL?
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
        fileReader: any FileReading = DefaultFileReader(),
        resolveFileToOpen: @escaping (URL) -> URL? = { DirectoryLister.resolveFileToOpen(at: $0) }
    ) {
        self.sessionStore = sessionStore
        self.windowManager = windowManager
        self.fileReader = fileReader
        self.resolveFileToOpen = resolveFileToOpen
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
        var seenWindows: Set<ObjectIdentifier> = []

        func group(for window: NSWindow) -> SessionLayout.TabGroup? {
            guard !seenWindows.contains(ObjectIdentifier(window)),
                  windowManager.viewerPath(of: window) != nil else { return nil }

            let tabWindows = window.tabGroup?.windows ?? [window]
            seenWindows.formUnion(tabWindows.map(ObjectIdentifier.init))

            let paths = tabWindows.compactMap { windowManager.viewerPath(of: $0) }
            guard !paths.isEmpty else { return nil }
            let selectedWindow = window.tabGroup?.selectedWindow ?? window
            return SessionLayout.TabGroup(
                paths: paths, selectedPath: windowManager.viewerPath(of: selectedWindow)
            )
        }

        // orderedWindows は最小化(Dock 収納)・非表示のウィンドウを含まないため、
        // NSApp.windows を後ろに連結し、残りのビューアウィンドウのグループを末尾に補完する。
        // compactMap は前から順に評価するため、seenWindows による重複除去はこの並びのまま効く。
        return SessionLayout(groups: (NSApp.orderedWindows + NSApp.windows).compactMap(group(for:)))
    }

    /// 「最近使ったリポジトリ」から選ばれたリポジトリを開く。
    /// savedTabGroup があり実在するパスが残っていればタブ構成ごと復元し、
    /// 無い/全て消えている場合はルート内の対応ファイルを解決してサイドバー表示で開く
    /// フォールバック(openRootFallback)へ縮退する。
    func openRepository(
        root: URL, savedTabGroup: SessionLayout.TabGroup?, options: CLIOpenOptions = CLIOpenOptions()
    ) {
        guard let savedTabGroup else {
            openRootFallback(root: root, options: options)
            return
        }
        let existingPaths = Set(savedTabGroup.paths.filter { path in
            fileReader.isExistingFile(at: URL(fileURLWithPath: path))
        })
        let filtered = SessionLayout(groups: [savedTabGroup]).filtered(to: existingPaths)
        guard let group = filtered.groups.first else {
            openRootFallback(root: root, options: options)
            return
        }
        let urlByPath = Dictionary(group.paths.map { ($0, URL(fileURLWithPath: $0)) }) { first, _ in first }
        restoreTabGroup(group, urlByPath: urlByPath, options: options)
    }

    /// タブ構成を復元できない場合のフォールバック。root はディレクトリなので、
    /// AppDelegate.openViewer(for:options:) と同じ経路(既定は DirectoryLister.resolveFileToOpen)で
    /// 中の対応ファイルへ解決してから開く。ViewerWindowManager.openViewer はファイルを渡す前提のため、
    /// ディレクトリをそのまま渡すと壊れたウィンドウになる(サイドバーが親ディレクトリを指す等)。
    /// 対応ファイルが1つも無い(空フォルダ等)場合は、壊れたウィンドウを開くより何もしない方を選ぶ
    /// (AppDelegate 側のノーファイルアラートは CLI 起動専用の導線のため、ここでは踏襲しない)。
    private func openRootFallback(root: URL, options: CLIOpenOptions) {
        guard let target = resolveFileToOpen(root) else { return }
        openViewer(for: target, options: options, forceSidebarVisible: true)
    }

    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    /// SessionLayout があればタブグループ構成・タブ順・選択タブを再現し、無ければ従来どおり開いた順に開く。
    /// 最後に前回アクティブだったファイルをキーウィンドウにする。
    /// `options`: パス引数なしの CLI 起動(`befold --hidden-files` 等)で指定された表示オプション。
    /// 隠しファイル表示は即座にアプリ全体へ、並び順・行番号・ソース/プレビューモードは
    /// これから復元する各ウィンドウへ適用する(この起動限りの上書きで、保存済み設定は書き換えない)。
    func restoreLastSession(options: CLIOpenOptions = CLIOpenOptions()) {
        if let showHiddenFiles = options.showHiddenFiles {
            windowManager.setHiddenFiles(showHiddenFiles)
        }

        // 復元中のウィンドウ表示がシステムの「タブ優先」設定で勝手にタブ結合しないよう、
        // 自動タブ化を一時的に無効にする(グループ構成は addTabbedWindow で明示的に再現する)
        let allowsTabbing = NSWindow.allowsAutomaticWindowTabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        defer { NSWindow.allowsAutomaticWindowTabbing = allowsTabbing }

        let existingURLs = urlsToRestore.filter { url in
            guard fileReader.isExistingFile(at: url) else {
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
                restoreTabGroup(group, urlByPath: urlByPath, options: options)
                restoredPaths.formUnion(group.paths)
            }
        }
        layoutToRestore = nil

        // レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く
        for url in existingURLs where !restoredPaths.contains(url.normalizedPathKey) {
            openViewer(for: url, options: options)
        }

        // 前回アクティブだったファイルをキーウィンドウにする(開けていなければ成り行きのまま)
        if let activePath = activePathToRestore,
           let window = windowManager.window(forPath: activePath)
        {
            window.makeKeyAndOrderFront(nil)
        }
        activePathToRestore = nil
    }

    /// CLI 起動オプションの上書きをまとめてウィンドウ生成へ引き渡す。
    /// restoreLastSession・タブグループ復元・ルートフォルダのフォールバックの
    /// いずれからも呼ぶことで、CLIOpenOptions にオーバーライドが追加されても転送漏れが起きないようにする。
    /// forceSidebarVisible はフォルダーオープン相当(openRootFallback)でのみ true にする。
    private func openViewer(for url: URL, options: CLIOpenOptions, forceSidebarVisible: Bool = false) {
        windowManager.openViewer(
            for: url, forceSidebarVisible: forceSidebarVisible,
            sidebarVisibleOverride: options.showSidebar,
            initialSortOrder: options.viewerSortOrder,
            showLineNumbersOverride: options.showLineNumbers, sourceModeOverride: options.sourceMode
        )
    }

    /// 1 つのタブグループを復元する。先頭のウィンドウに残りを順にタブ連結し、選択タブを再現する。
    private func restoreTabGroup(
        _ group: SessionLayout.TabGroup, urlByPath: [String: URL], options: CLIOpenOptions
    ) {
        var previousWindow: NSWindow?
        for path in group.paths {
            guard let url = urlByPath[path] else { continue }
            openViewer(for: url, options: options)
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
