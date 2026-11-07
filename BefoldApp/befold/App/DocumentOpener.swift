import AppKit
import BefoldKit

/// URL をビューアウィンドウで開く唯一の入口。
///
/// 「開く」要求は CLI・Recent メニュー・Dock へのドロップ・参照クリック・ファイル選択パネル・
/// Quick Open と入口が多い。解決(実 FS アクセス)と逐次化の作法をここへ集約し、
/// 呼び出し側は経路を問わず同じ順序保証を受け取る。
@MainActor
final class DocumentOpener {
    private let windowManager: ViewerWindowManager
    private let activeViewer: ActiveViewerProvider.Provide
    private let activeBlankTab: ActiveViewerProvider.ProvideBlankTab
    /// 空タブを起点にした直前の要求。解決はファイルごとに時間が違うので、続けて選ぶと後の要求が
    /// 先に開いて手前を奪われる。空タブを起点にする要求(UI からのオープン・ドロップ・パネル)だけを
    /// 選んだ順に開く。起点が文書タブなら待たない(遅いボリュームの解決で他の要求を止めない)。
    private var lastBlankTabOpen: Task<Void, Never>?

    /// 空タブを起点にする要求を、前の要求の後に並べる。
    private func enqueueBlankTabOpen(
        from sourceWindow: NSWindow?, _ work: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let isBlankOrigin = sourceWindow?.windowController is BlankTabWindowController
            || (sourceWindow as? ViewerDocumentWindow)?.replacement != nil
        guard isBlankOrigin else { return Task { await work() } }
        let previous = lastBlankTabOpen
        let opening = Task {
            await previous?.value
            await work()
        }
        lastBlankTabOpen = opening
        return opening
    }

    /// - Parameters:
    ///   - windowManager: ウィンドウ生成先。全ウィンドウで共有する 1 個を渡す
    ///     (既定値を持たせない。渡し忘れがコンパイルエラーにならず別インスタンスになるため)。
    ///   - activeViewer: ファイル選択パネルの初期ディレクトリを決めるための現在のビューア。
    init(
        windowManager: ViewerWindowManager, activeViewer: @escaping ActiveViewerProvider.Provide,
        activeBlankTab: @escaping ActiveViewerProvider.ProvideBlankTab
    ) {
        self.windowManager = windowManager
        self.activeViewer = activeViewer
        self.activeBlankTab = activeBlankTab
    }

    /// Open Recent・ブックマーク・DocumentController など、記憶済みのリストから開く入口。
    ///
    /// 既にどこかの窓で開いていればその窓を前面に出す(手前が文書タブでも空タブでも同じ結果に
    /// する。空タブは残す)。開いていなければ手前の空タブを置き換える。ディレクトリが渡された
    /// 場合は、フォルダー内最初のファイルを開く。拡張子を問わずウィンドウは開かれ、未対応の内容
    /// ならビューア側でプレースホルダー表示する。フォーカスは本文へ移さない(本文へ移す
    /// Quick Open と CLI はそれぞれ `openInActiveTab` と `openPaths` を通る)。
    @discardableResult
    func openViewer(for url: URL) -> Task<Void, Never> {
        openFromInterface(url, focusesContent: false, prefersExistingWindow: true)
    }

    /// Quick Open の入口。手前のタブで開く。文書タブの Quick Open が別の窓の同じファイルを前面に
    /// 出さずに手前で切り替えるのと同じ規則で、手前が空タブならそれを置き換える。
    @discardableResult
    func openInActiveTab(_ url: URL) -> Task<Void, Never> {
        openFromInterface(url, focusesContent: true, prefersExistingWindow: false)
    }

    private func openFromInterface(_ url: URL, focusesContent: Bool, prefersExistingWindow: Bool) -> Task<Void, Never> {
        let blankWindow = activeBlankTab()?.window
        return enqueueBlankTabOpen(from: blankWindow) { [self] in
            await openViewer(
                for: url, options: CLIOpenOptions(), relativeTo: blankWindow, focusesContent: focusesContent,
                prefersExistingWindow: prefersExistingWindow
            )
        }
    }

    /// 参照クリック由来のオープン。disposition/relativeTo をそのまま ViewerWindowManager へ通す。
    func openViewer(
        for url: URL, disposition: OpenDisposition, placement: NewTabPlacement, relativeTo sourceWindow: NSWindow?
    ) {
        Task {
            await openViewer(
                for: url, options: CLIOpenOptions(),
                disposition: disposition, placement: placement, relativeTo: sourceWindow
            )
        }
    }

    /// CLI から渡されたパス群を、表示オプション付きでそれぞれ別ウィンドウに開く。
    ///
    /// `--hidden-files`/`--no-hidden-files` は `--sort` と同じ**その起動限りの窓単位の上書き**で、
    /// 保存された既定値は書き換えない(TASK-480.3)。パスがあるときは options がそのまま
    /// 各ウィンドウへ流れるのでここでは何もしない。
    /// パス無し起動でここへ来るのは `--hidden-files` 単独のときだけ(それ以外の表示オプションは
    /// 対象の文書を要するため CLI のパース段階で弾かれる = `CLIOpenOptions.requiresPaths`)。
    /// その場合だけ適用先の窓が決まらないため、いま操作対象になっている窓へ適用する。
    func openPaths(_ paths: [String], options: CLIOpenOptions) {
        guard !paths.isEmpty else {
            if let controller = activeViewer() {
                ViewerDisplayOptionsApplier.apply(options, to: controller, forceSidebarVisible: false)
            }
            return
        }
        // CLI で開いた窓は本文にフォーカスを置く（TASK-584）。サイドバーを操作して
        // 開いたわけではないので、本文に居るのが妥当。
        openSequentially(
            paths.map { URL(fileURLWithPath: $0) }, options: options,
            disposition: options.openDisposition, focusesContent: true
        )
    }

    /// 複数の URL を、渡された順にウィンドウが出るよう逐次に開く。
    /// タブを開く `openInTabs` と同じ `SequentialOpener` で逐次化する。1 件ずつ `openViewer(for:)` を呼ぶと
    /// 呼び出しごとに Task が張られ、解決(実 FS アクセス)の完了順でウィンドウ順序が入れ替わる。
    func openSequentially(
        _ urls: [URL], options: CLIOpenOptions = CLIOpenOptions(),
        disposition: OpenDisposition = .currentTab, focusesContent: Bool = false
    ) {
        guard !urls.isEmpty else { return }
        Task {
            await SequentialOpener.open(urls) {
                await openViewer(
                    for: $0, options: options, disposition: disposition, focusesContent: focusesContent
                )
            }
        }
    }

    /// ファイル選択パネルを表示し、選択されたファイルをビューアで開く。
    /// 初期ディレクトリは手前の窓が表示中のファイルのディレクトリか空タブのサイドバーのフォルダ、
    /// 無ければ（未オープン含む）ホームディレクトリを使う。
    func presentOpenPanel() {
        let controller = activeViewer()
        let blank = activeBlankTab()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = OpenPanelDirectoryResolver.resolve(
            currentFileDirectory: controller?.fileURL.deletingLastPathComponent() ?? blank?.sidebarDirectory,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            if let blank {
                // パネルの表示中に空タブが閉じても置き換わっても、行き先は openViewer の入口が決める。
                guard let window = blank.window else { return }
                self?.openInTabs(panel.urls, relativeTo: window)
                return
            }
            // 複数選択は選択順にウィンドウが出る必要がある。1 件ずつ openViewer(for:) を
            // 呼ぶと呼び出しごとに Task が張られ、順序が任意になる(openSequentially の doc)。
            self?.openSequentially(panel.urls)
        }
    }

    /// 選択順にタブを開き、最初の文書だけを選択する。空タブは最初の成功時に置き換える。
    @discardableResult
    func openInTabs(_ urls: [URL], relativeTo sourceWindow: NSWindow) -> Task<Void, Never> {
        enqueueBlankTabOpen(from: sourceWindow) { [self] in
            var anchor = sourceWindow
            var selected: NSWindow?
            await SequentialOpener.open(urls) { url in
                guard let opened = await openViewer(
                    for: url, options: CLIOpenOptions(),
                    disposition: ViewerWindowOpenPolicy.tabBatchDisposition(relativeTo: anchor), relativeTo: anchor,
                    allowsDirectories: false
                ), let window = opened.window else { return }
                if selected == nil {
                    selected = window
                    anchor = window
                    ViewerTabGrouping.selectTab(window)
                }
            }
            if let selected { ViewerTabGrouping.selectTab(selected) }
        }
    }

    /// ディレクトリ判定とオープン対象の解決は実 FS の存在確認・列挙を伴い、ネットワーク
    /// ボリューム上ではウィンドウを出す前に停止しうる。解決だけメインアクターの外へ逃がし、
    /// ウィンドウ生成は戻ってから行う。
    @discardableResult
    private func openViewer(
        for url: URL, options: CLIOpenOptions,
        disposition: OpenDisposition = .currentTab, placement: NewTabPlacement = .end,
        relativeTo sourceWindow: NSWindow? = nil, focusesContent: Bool = false, allowsDirectories: Bool = true,
        prefersExistingWindow: Bool = false
    ) async -> ViewerWindowController? {
        let resolved = await withBlockingWork {
            (isDirectory: DirectoryLister.isDirectory(url), target: DirectoryLister.resolveFileToOpen(at: url))
        }
        // 既にどこかで開いていれば、起点の空タブに関わらず既存の窓を前面に出す。
        let reusesExisting = prefersExistingWindow && resolved.target.map(windowManager.hasReusableWindow(for:)) == true
        let isDirectory = resolved.isDirectory
        if isDirectory, !allowsDirectories { return nil }
        guard let target = resolved.target else {
            presentNoFileAlert()
            return nil
        }
        // 解決を待つ間に起点が閉じた・置き換わった場合の行き先は、openViewer の入口が決める(TASK-917)。
        let controller = windowManager.openViewer(
            for: target, options: options, disposition: reusesExisting ? .currentTab : disposition,
            relativeTo: reusesExisting ? nil : sourceWindow,
            tabPlacement: placement, forceSidebarVisible: isDirectory
        )
        if focusesContent { controller?.focusContentSurface(nil) }
        return controller
    }

    private func presentNoFileAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "cli.folder.noFile", bundle: .l10n)
        alert.runModal()
    }
}
