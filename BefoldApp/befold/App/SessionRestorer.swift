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
    /// openRootFallback が対応ファイルを解決できなかった場合の通知シーム。既定は実際に
    /// モーダルアラートを表示する FileNotFoundUI.present だが、テストでは実アラートを
    /// 出さずに呼び出しだけ記録するスタブに差し替えられるようにする。
    private let presentFileNotFound: (URL) -> Void
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
        resolveFileToOpen: @escaping (URL) -> URL? = { DirectoryLister.resolveFileToOpen(at: $0) },
        presentFileNotFound: @escaping (URL) -> Void = { FileNotFoundUI.present(url: $0, over: nil) }
    ) {
        self.sessionStore = sessionStore
        self.windowManager = windowManager
        self.fileReader = fileReader
        self.resolveFileToOpen = resolveFileToOpen
        self.presentFileNotFound = presentFileNotFound
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
                  ViewerTabGrouping.viewerPath(of: window) != nil else { return nil }

            seenWindows.formUnion(ViewerTabGrouping.tabWindows(of: window).map(ObjectIdentifier.init))

            // 組み立て規則は ViewerTabGrouping.tabGroup(of:) に一本化してある
            // (「最近使ったリポジトリ」のタブ構成と同じ形式で相互に復元されるため)
            return ViewerTabGrouping.tabGroup(of: window)
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
        let restoration = restoreLayout(
            SessionLayout(groups: [savedTabGroup]),
            candidates: savedTabGroup.paths.map { (key: $0, url: URL(fileURLWithPath: $0)) },
            options: options
        )
        // 実在するパスが 1 つも残らなければタブ構成は復元できていない。
        if restoration.restoredPaths.isEmpty {
            openRootFallback(root: root, options: options)
        }
    }

    /// レイアウト復元の結果。
    private struct LayoutRestoration {
        /// 実在が確認できた候補。渡された順を保つ(復元順・追加オープン順の基準)。
        let existing: [(key: String, url: URL)]
        /// 実際に復元したタブのパスキー。
        let restoredPaths: Set<String>
    }

    /// 「候補を実在ファイルで絞る → パスキーで URL を引ける形にする → レイアウトを絞る →
    /// タブグループを順に復元する」という復元経路の単一の実装元。
    /// セッション復元(restoreLastSession)と最近使ったリポジトリ(openRepository)で共有する。
    /// - Parameter candidates: (レイアウト上のパスキー, 開く URL) の組。キーは呼び出し元が決める
    ///   (保存済みレイアウトのパス文字列と一致させる必要があるため、ここで正規化し直さない)。
    /// - Parameter onMissing: 実在しなかった候補ごとに、ウィンドウを 1 つも開く前に呼ぶ。
    ///   セッション記録から消えたファイルを取り除くのに使う。
    private func restoreLayout(
        _ layout: SessionLayout,
        candidates: [(key: String, url: URL)],
        options: CLIOpenOptions,
        onMissing: (URL) -> Void = { _ in }
    ) -> LayoutRestoration {
        // 実在判定は 1 度だけ行い、その結果から「開く候補」と「消えた候補の通知」を分ける。
        // filter の述語内で onMissing を呼ぶと、lazy 化や短絡評価が入った途端に
        // 通知が走らなくなる(セッション記録から消えたファイルが取り除かれない)。
        let checked = candidates.map { (candidate: $0, exists: fileReader.isExistingFile(at: $0.url)) }
        for entry in checked where !entry.exists {
            onMissing(entry.candidate.url)
        }
        let existing = checked.filter(\.exists).map(\.candidate)

        let urlByPath = Dictionary(existing.map { ($0.key, $0.url) }) { first, _ in first }

        let groups = layout.filtered(to: Set(urlByPath.keys)).groups
        // 同じパスが複数グループに現れる場合に、2 件目以降を新しいウィンドウとして開くための
        // 追跡。グループをまたいで持ち回る必要があるため、restoreTabGroup の外に置く。
        var openedPaths: Set<String> = []
        for group in groups {
            restoreTabGroup(
                group, urlByPath: urlByPath, options: options, openedPaths: &openedPaths
            )
        }
        return LayoutRestoration(existing: existing, restoredPaths: Set(groups.flatMap(\.paths)))
    }

    /// タブ構成を復元できない場合のフォールバック。root はディレクトリなので、
    /// AppDelegate.openViewer(for:options:) と同じ経路(既定は DirectoryLister.resolveFileToOpen)で
    /// 中の対応ファイルへ解決してから開く。ViewerWindowManager.openViewer はファイルを渡す前提のため、
    /// ディレクトリをそのまま渡すと壊れたウィンドウになる(サイドバーが親ディレクトリを指す等)。
    /// root 自体が消えている(worktree 削除等)場合は resolveFileToOpen が nil を返すため、
    /// ViewerWindowManager.openViewer と同じ FileNotFoundUI で通知する(空フォルダ等、root は
    /// 実在するが対応ファイルが1つも無いケースと区別しない。どちらも「開けなかった」と伝わればよい)。
    private func openRootFallback(root: URL, options: CLIOpenOptions) {
        guard let target = resolveFileToOpen(root) else {
            presentFileNotFound(root)
            return
        }
        openViewer(for: target, options: options, forceSidebarVisible: true)
    }

    /// 前回セッションで開いていたファイルを再オープンする。存在しなくなったファイルは記録からも取り除く。
    /// SessionLayout があればタブグループ構成・タブ順・選択タブを再現し、無ければ従来どおり開いた順に開く。
    /// 最後に前回アクティブだったファイルをキーウィンドウにする。
    /// `options`: 復元するウィンドウへ与える表示オプション。隠しファイル表示を含め、
    /// すべて各ウィンドウへ適用する(この起動限りの上書きで、保存済み設定は
    /// 書き換えない / TASK-480.3)。本番の呼び出し元(AppDelegate)は既定値で呼ぶ。CLI 由来のオプションは
    /// パス引数を要するようになったため(`CLIOpenOptions.requiresPaths`)、この経路ではなく
    /// `openPaths` から届く。options をフィールド単位で手写しせずそのまま
    /// `ViewerWindowManager.openViewer` へ渡す形は、経路ごとの取りこぼしを防ぐために保つ。
    func restoreLastSession(options: CLIOpenOptions = CLIOpenOptions()) {
        // 復元中のウィンドウ表示がシステムの「タブ優先」設定で勝手にタブ結合しないよう、
        // 自動タブ化を一時的に無効にする(グループ構成は明示的なタブ結合で再現する)
        let allowsTabbing = NSWindow.allowsAutomaticWindowTabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        defer { NSWindow.allowsAutomaticWindowTabbing = allowsTabbing }

        let restoration = restoreLayout(
            layoutToRestore ?? SessionLayout(groups: []),
            candidates: urlsToRestore.map { (key: $0.normalizedPathKey, url: $0) },
            options: options,
            onMissing: { [sessionStore] url in sessionStore.noteClosed(url) }
        )
        urlsToRestore = []
        layoutToRestore = nil

        // レイアウトに無いファイル(クラッシュ後に開いたもの等)は従来どおり開いた順に開く
        for candidate in restoration.existing where !restoration.restoredPaths.contains(candidate.key) {
            openViewer(for: candidate.url, options: options)
        }

        // 前回アクティブだったファイルをキーウィンドウにする(開けていなければ成り行きのまま)
        if let activePath = activePathToRestore,
           let window = windowManager.window(forPath: activePath)
        {
            window.makeKeyAndOrderFront(nil)
        }
        activePathToRestore = nil
    }

    /// CLI 起動オプションをまとめてウィンドウ生成へ引き渡す。
    /// forceSidebarVisible はフォルダーオープン相当(openRootFallback)でのみ true にする。
    private func openViewer(for url: URL, options: CLIOpenOptions, forceSidebarVisible: Bool = false) {
        windowManager.openViewer(for: url, options: options, forceSidebarVisible: forceSidebarVisible)
    }

    /// 1 つのタブグループを復元する。先頭のウィンドウに残りを順にタブ連結し、選択タブを再現する。
    ///
    /// ウィンドウは `openViewer` の戻り値で受け取り、`window(forPath:)` では引き直さない。
    /// `controllers` は 1 パスに複数のコントローラを持つ多重マップなので、引き直すと同じパスの
    /// 別ウィンドウ(先に復元した他グループのもの)を掴み、`addTabbedWindow` がその生きている
    /// ウィンドウを前のグループから奪う(TASK-415)。選択タブも同じ理由で、パスではなく
    /// このループで開いたウィンドウの同一性で決める。
    ///
    /// - Parameter openedPaths: この復元で既にウィンドウを開いたパス。同じパスが複数の
    ///   グループ(または同一グループ内)に現れる保存レイアウトは正当なので、2 件目以降は
    ///   `.newWindow` で新しいウィンドウとして復元する(`.currentTab` の重複抑止に当たると
    ///   ウィンドウが作られず、保存時より 1 つ少ないタブ構成になる)。
    private func restoreTabGroup(
        _ group: SessionLayout.TabGroup, urlByPath: [String: URL], options: CLIOpenOptions,
        openedPaths: inout Set<String>
    ) {
        var previousWindow: NSWindow?
        var selectedWindow: NSWindow?
        for path in group.paths {
            guard let url = urlByPath[path] else { continue }
            let disposition: OpenDisposition = openedPaths.contains(path) ? .newWindow : .currentTab
            let controller = windowManager.openViewer(
                for: url, options: options, disposition: disposition
            )
            openedPaths.insert(path)
            guard let window = controller?.window else { continue }
            // システムの「書類を開くときはタブで開く」設定に依存しないよう明示的にタブ化する
            ViewerTabGrouping.attachAsTab(window, to: previousWindow, select: false)
            previousWindow = window
            if path == group.selectedPath { selectedWindow = window }
        }
        selectedWindow?.tabGroup?.selectedWindow = selectedWindow
        // 復元は選択タブをプログラムから決めるため、キー化を待たずに一覧を揃える
        // (背面のグループはキーにならないので didBecomeKey 経由では届かない)。
        windowManager.syncWindowsMenuMembership()
    }
}
