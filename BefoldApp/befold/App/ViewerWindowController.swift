import AppKit
import BefoldKit
import SwiftUI
import WebKit

/// ViewerWindowController のウィンドウイベント(クローズ・rename・キー化など)を
/// 上位のウィンドウ管理層へ通知するプロトコル。ViewerWindowManager が実装する。
@MainActor
protocol ViewerWindowControllerDelegate: AnyObject {
    func viewerWindowWillClose(_ controller: ViewerWindowController)
    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController)
    func viewerWindow(_ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL)
    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    )
    func viewerWindow(
        _ controller: ViewerWindowController, isFileOpenInAnotherWindow url: URL
    ) -> Bool
    func viewerWindow(_ controller: ViewerWindowController, focusWindowForFile url: URL)
    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController)
}

/// モード切替セグメントコントロールのセグメント位置(0=プレビュー, 1=ソース)。
private enum ModeSegment: Int, Sendable {
    case preview = 0
    case source = 1
}

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController {
    /// 最後に調整したウィンドウフレーム（位置＋サイズ）の保存キー。全ウィンドウで共有する。
    private static let lastWindowFrameKey = "LastWindowFrame"
    private static let defaultContentSize = NSSize(width: 1100, height: 850)
    private static let modeToggleItemIdentifier = NSToolbarItem.Identifier("modeToggle")
    private static let backItemIdentifier = NSToolbarItem.Identifier("historyBack")
    private static let forwardItemIdentifier = NSToolbarItem.Identifier("historyForward")
    private static let lineNumbersItemIdentifier = NSToolbarItem.Identifier("lineNumbers")

    private let defaults: UserDefaults
    private let store: ViewerStore
    private let zoomStore: ZoomStore
    private let scrollPositionStore: ScrollPositionStore
    private let sourceModeStore: SourceModeStore
    private let hiddenFilesPreference: HiddenFilesPreference
    private let findOptionsPreference: FindOptionsPreference
    private let forceSidebarVisible: Bool
    /// 二本指スワイプ検知用のローカルイベントモニタ。ウィンドウが閉じたら解除する。
    private var scrollEventMonitor: Any?
    /// スワイプジェスチャー中(.began〜.changed)に積算する水平デルタ。.ended で判定に使う。
    private var swipeHorizontalAccumulator: CGFloat = 0
    /// スワイプジェスチャー中(.began〜.changed)に積算する垂直デルタ。.ended で判定に使う。
    private var swipeVerticalAccumulator: CGFloat = 0
    /// スワイプしきい値(pt)。この値未満の水平デルタはナビゲーションしない。
    private static let swipeThreshold: CGFloat = 40
    private let webViewProxy = WebViewProxy()
    private(set) var isSourceMode = false
    private(set) var fileURL: URL
    /// サイドバー(一覧・選択同期・フォルダ移動)と戻る/進む履歴を担うナビゲータ。
    let sidebar: SidebarNavigator
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    var fileListModel: FileListModel {
        sidebar.fileListModel
    }

    /// ウィンドウイベントの通知先。ViewerWindowManager が実装する。
    weak var delegate: ViewerWindowControllerDelegate?

    // MARK: - Initialization

    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate → ViewerWindowManager から
    ///   注入される単一の共有インスタンスを渡すこと。デフォルト値は、不可視ファイル挙動に
    ///   無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter sourceModeStore: 同上。ソース表示モード挙動に無関心なテストが省略できるようにする。
    /// - Parameter scrollPositionStore: 同上。スクロール位置挙動に無関心なテストが省略できるようにする。
    init(
        fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        sourceModeStore: SourceModeStore = SourceModeStore(),
        scrollPositionStore: ScrollPositionStore = ScrollPositionStore(),
        forceSidebarVisible: Bool = false
    ) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.scrollPositionStore = scrollPositionStore
        self.sourceModeStore = sourceModeStore
        self.defaults = defaults
        self.hiddenFilesPreference = hiddenFilesPreference
        self.findOptionsPreference = findOptionsPreference
        self.forceSidebarVisible = forceSidebarVisible
        store = ViewerStore()
        let parentDir = fileURL.deletingLastPathComponent()
        let entries = DirectoryLister.listEntries(
            in: parentDir, sortOrder: .foldersFirst, showHiddenFiles: hiddenFilesPreference.showHiddenFiles
        )
        sidebar = SidebarNavigator(
            currentDirectory: parentDir, entries: entries, selection: fileURL,
            hiddenFilesPreference: hiddenFilesPreference
        )

        // ウィンドウの実サイズは contentViewController 設定後に確定させるため、
        // ここでの contentRect はプレースホルダ
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 400, height: 300)
        // コンテンツの地の色はウィンドウ背景が唯一の定義(ViewerTheme.canvas)。
        // WebView は透過(drawsBackground=false)のためこの色が透けて見える
        window.backgroundColor = ViewerTheme.canvas
        // 標準タイトルバーは背景色の上にマテリアルを重ねるため、背景色を
        // 揃えてもわずかに明るく描かれる。透過させて背景色を直接見せ、
        // 区切り線も消してコンテンツと完全に地続きにする
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.title = fileURL.lastPathComponent
        // タイトルバーにプロキシアイコンを表示し、Cmd+クリックのパス表示・
        // タイトルバーからのドラッグを有効にする
        window.representedURL = fileURL
        window.tabbingIdentifier = "ViewerWindow"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbarStyle = .unified

        super.init(window: window)

        // toolbar.delegate は self を使うため super.init の後に設定する。
        // window.toolbar もデリゲート設定後に代入しないとアイテムが空になる。
        toolbar.delegate = self
        window.toolbar = toolbar

        // contentViewController の設定でウィンドウがビューのフィッティングサイズに
        // リサイズされるため、フレームの確定はその後に行う。
        // frameDescriptor はフレーム座標系で保存・復元されるため、
        // タイトルバー高さの混入によるサイズのずれは起きない
        window.contentViewController = makeSplitViewController()
        if let descriptor = defaults.string(forKey: Self.lastWindowFrameKey) {
            window.setFrame(from: descriptor)
            // 共有フレームをそのまま使うと復元・複数同時オープンでウィンドウが
            // 完全に重なるため、既存ウィンドウと位置が一致する場合だけずらす。
            offsetFrameToAvoidOverlap(window)
        } else {
            window.setContentSize(Self.defaultContentSize)
            window.center()
        }

        // delegate の設定はフレーム確定後にする。init 中のリサイズ
        // (contentViewController 設定によるフィッティングサイズ化など)が
        // windowDidResize 経由で保存されるのを防ぐ
        window.delegate = self

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheelForHistorySwipe(event)
            return event
        }

        sidebar.attach(to: self)
        store.onFileGone = { [weak self] in
            self?.window?.close()
        }
        store.onFileRenamed = { [weak self] newURL in
            self?.handleRename(to: newURL)
        }
        store.onContentReloaded = { [weak self] in
            self?.updateModeToggleAppearance()
            self?.updateLineNumbersToolbarItem()
        }
        store.openFile(fileURL)
        // 直接開いた場合も、切替(performFileSwitch)と同じく保存済みのソース表示モードを復元する。
        // applySourceMode が内部で updateModeToggleAppearance() を呼ぶため、ここでの明示呼び出しは不要。
        applySourceMode(sourceModeStore.restoredSourceMode(for: fileURL))
        sidebar.recordHistory()
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView)を並べる split view controller を組み立てる。
    private func makeSplitViewController() -> NSViewController {
        let contentView = ViewerContentView(
            store: store,
            zoomStore: zoomStore,
            scrollPositionStore: scrollPositionStore,
            findOptionsPreference: findOptionsPreference,
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: fileURL)
            },
            onScrollPositionChanged: { [weak self] position, mode in
                guard let self else { return }
                scrollPositionStore.setScrollPosition(position, for: fileURL, mode: mode)
            },
            onOpenReference: { [weak self] href, newWindow in
                self?.handleOpenReference(href: href, newWindow: newWindow)
            },
            webViewProxy: webViewProxy
        )
        let fileListView = FileListView(
            model: fileListModel,
            onSelect: { [weak self] url in self?.switchFile(to: url) },
            onNavigate: { [weak self] url in self?.navigateToFolder(url) },
            onSortOrderChanged: { [weak self] order in
                guard let self else { return }
                fileListModel.sortOrder = order
                sidebar.refreshFileList()
            },
            onOpenInNewWindow: { url in
                AppDelegate.shared?.openViewer(for: url)
            },
            onToggleHiddenFiles: { [weak self] in
                guard let self else { return }
                delegate?.viewerWindowDidToggleHiddenFiles(self)
            }
        )
        return ViewerSplitViewController(
            sidebar: fileListView,
            content: contentView,
            forceSidebarVisible: forceSidebarVisible
        )
    }

    /// リンク/パス参照のアクティベーションを処理する。
    /// テスト(@testable import)から回帰テストとして直接呼べるよう internal にする（外部公開はしない）。
    func handleOpenReference(href: String, newWindow: Bool) {
        let target = ReferenceResolver.resolve(href: href, baseURL: fileURL)
        switch target {
        case let .external(url):
            NSWorkspace.shared.open(url)
        case let .localFile(url):
            var isDir: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                !isDir.boolValue
            else {
                showFileNotFoundAlert(url: url)
                return
            }
            if newWindow {
                AppDelegate.shared?.openViewer(for: url)
            } else {
                switchFile(to: url)
            }
        case .unsupported:
            break
        }
    }

    private func showFileNotFoundAlert(url: URL) {
        // window があればシート、無ければモーダルで表示する(判定は FileNotFoundUI 側)。
        FileNotFoundUI.present(url: url, over: window)
    }

    /// ファイルの rename / move をウィンドウに反映する。
    /// リネームは同一ファイルの改名であり、内容・表示倍率・ビューモードは原則保持する。
    func handleRename(to newURL: URL) {
        let oldURL = fileURL
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        applyURLToWindow(newURL)

        // 実体は同じファイルなので旧パスの倍率・ソース表示モードを新パスへ引き継ぐ
        // (旧パスはもう存在しない)。
        zoomStore.migrateZoom(from: oldURL, to: newURL)
        sourceModeStore.migrateSourceMode(from: oldURL, to: newURL)
        scrollPositionStore.migrateScrollPosition(from: oldURL, to: newURL)
        // 内容は不変なのでビューモードは維持する。ただし対応形式が変わり
        // (例: .md → .swift、.md → .png)ソース表示トグルが成立しなくなる
        // 場合のみリセットする。
        // store.handleRename が loadContent 経由で onContentReloaded を発火済みのため、
        // ここでの明示的な updateModeToggleAppearance() 呼び出しは不要
        // (resetSourceMode() が走る場合は applySourceMode 内で再同期される)。
        if isSourceMode, !FileType(url: newURL).supportsSourceMode {
            resetSourceMode()
        }
        let newDir = newURL.deletingLastPathComponent()
        if newDir.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        {
            fileListModel.currentDirectory = newDir
        }
        sidebar.refreshFileList()
        delegate?.viewerWindow(self, didRenameFrom: oldURL, to: newURL)
        sidebar.applyRename(from: oldURL, to: newURL)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    /// ファイル切替の実処理のみ担い、選択同期・履歴記録は SidebarNavigator へ委譲する。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        if delegate?.viewerWindow(self, isFileOpenInAnotherWindow: newURL) == true {
            delegate?.viewerWindow(self, focusWindowForFile: newURL)
            sidebar.restoreSelection(to: oldURL)
            return
        }
        guard performFileSwitch(to: newURL) else {
            sidebar.restoreSelection(to: oldURL)
            return
        }
        sidebar.syncAfterSwitch(to: newURL)
    }

    /// ウィンドウのタイトルと representedURL を新しい URL に合わせて更新する。
    /// handleRename / switchFile 共通の表示更新。
    private func applyURLToWindow(_ newURL: URL) {
        fileURL = newURL
        guard let window else { return }
        window.title = newURL.lastPathComponent
        window.representedURL = newURL
    }

    /// 現在のファイルの保存倍率を WebView に適用する。
    /// 初期ロード時の倍率注入(ViewerBridge.initialZoomScript)と同じ経路で
    /// window._mmdInitialZoom を書き換え、viewer.html の初期化関数で反映させる。
    private func applyStoredZoomToWebView() {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(ViewerBridge.applyZoomScript(zoomStore.zoom(for: fileURL)))
    }

    /// サイドバーで別フォルダーへ移動する。詳細は SidebarNavigator に委譲する。
    func navigateToFolder(_ url: URL) {
        sidebar.navigateToFolder(url)
    }

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        sidebar.navigateHistory(by: offset)
    }

    /// switchFile と履歴適用が共有するファイル切替の実処理。
    /// 切替先ファイルの保存済みビューモードの復元、URL 更新、コンテンツ読込、
    /// ズーム適用、コールバック通知を行う。
    /// 切替先が存在しない場合はアラートを表示して false を返す(状態は変更しない)。
    @discardableResult
    func performFileSwitch(to newURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: newURL.path) else {
            showFileNotFoundAlert(url: newURL)
            return false
        }
        let oldURL = fileURL
        // fileURL・viewMode を書き換える前に、退場側(oldURL・現在のモード)の
        // スクロール位置を明示的なキーで確定保存する。切替後に保存すると
        // 退場側の位置が入場側ファイルのキーへ誤って保存されるため、順序が重要。
        saveCurrentScrollPosition(for: oldURL, mode: isSourceMode ? .source : .rendered)
        let restoredSourceMode = sourceModeStore.restoredSourceMode(for: newURL)
        applySourceMode(restoredSourceMode)
        applyURLToWindow(newURL)
        // fileExists を確認済みなので store.openFile は必ず loadContent → onContentReloaded まで
        // 到達し、そこで updateModeToggleAppearance() が発火する。ここでの明示呼び出しは不要。
        store.openFile(newURL)
        applyStoredZoomToWebView()
        delegate?.viewerWindow(self, didSwitchFileFrom: oldURL, to: newURL)
        return true
    }

    /// WebView に現在のスクロール位置を問い合わせ、指定した URL・モードのキーへ保存する。
    /// ファイル/モード切替の直前に、切替後の self.fileURL / isSourceMode に依存せず
    /// 退場側の位置を確定させるために使う(render() 冒頭の同期通知を廃止した代替)。
    private func saveCurrentScrollPosition(for url: URL, mode: ViewerBridge.ViewMode) {
        guard let webView = webViewProxy.webView else { return }
        webView.evaluateJavaScript(ViewerBridge.currentScrollPositionScript) { [scrollPositionStore] result, _ in
            guard let position = (result as? NSNumber)?.doubleValue else { return }
            scrollPositionStore.setScrollPosition(position, for: url, mode: mode)
        }
    }

    /// 既存のビューアウィンドウと位置が完全に一致する場合だけ、標準のカスケード量ずらす。
    /// cascadeTopLeft(from:) は移動先を戻り値で返すため、戻り値を自分に適用する。
    /// ずらした先が別ウィンドウと一致することがあるので、重ならなくなるまで繰り返す。
    private func offsetFrameToAvoidOverlap(_ window: NSWindow) {
        func overlapsExisting() -> Bool {
            NSApp.windows.contains { other in
                other !== window
                    && other.isVisible
                    && other.windowController is ViewerWindowController
                    && other.frame.origin == window.frame.origin
            }
        }
        var attempts = 0
        while overlapsExisting(), attempts < 20 {
            let shifted = window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY))
            window.setFrameTopLeftPoint(shifted)
            attempts += 1
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - SidebarNavigatorHost

extension ViewerWindowController: SidebarNavigatorHost {
    /// SidebarNavigator が現在ファイルを都度参照するための橋渡し。
    var currentFileURL: URL {
        fileURL
    }

    /// 指定 URL が自分以外のウィンドウで開かれているか(注入されたチェックへ委譲)。
    func isFileOpenElsewhere(_ url: URL) -> Bool {
        delegate?.viewerWindow(self, isFileOpenInAnotherWindow: url) ?? false
    }

    /// 履歴状態の変化をツールバーの戻る/進むアイテムへ反映する。
    func historyStateDidChange() {
        window?.toolbar?.items
            .filter {
                $0.itemIdentifier == Self.backItemIdentifier
                    || $0.itemIdentifier == Self.forwardItemIdentifier
            }
            .forEach { updateHistoryToolbarItem($0) }
    }
}

// MARK: - Menu Actions / Validation / NSWindowDelegate

extension ViewerWindowController: NSWindowDelegate {
    /// 現在のウィンドウフレーム（位置＋サイズ）を保存する。
    /// フルスクリーン中のフレームは通常ウィンドウの寸法として無意味なため保存しない。
    private func saveWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        defaults.set(window.frameDescriptor, forKey: Self.lastWindowFrameKey)
    }

    /// 直接 HTML モードでは pageZoom を transform で変換して保存し、
    /// それ以外は viewer.js のズーム実装(script)へ委譲する。
    private func performZoom(
        directHTML transform: (Double) -> Double, script: String
    ) {
        guard let webView = webViewProxy.webView else { return }
        if webViewProxy.isDirectHTMLMode {
            let newZoom = transform(webView.pageZoom)
            webView.pageZoom = newZoom
            zoomStore.setZoom(newZoom, for: fileURL)
        } else {
            webView.evaluateJavaScript(script)
        }
    }

    /// View > Zoom In。HTML 直接ロード時は WKWebView の pageZoom を、それ以外は JS ズーム実装を使う。
    @objc func zoomIn(_ sender: Any?) {
        performZoom(
            directHTML: { min(ZoomStore.maxZoom, $0 + ZoomStore.zoomStep) },
            script: ViewerBridge.zoomInScript
        )
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        performZoom(
            directHTML: { max(ZoomStore.minZoom, $0 - ZoomStore.zoomStep) },
            script: ViewerBridge.zoomOutScript
        )
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        performZoom(
            directHTML: { _ in ZoomStore.defaultZoom },
            script: ViewerBridge.zoomResetScript
        )
    }

    /// File > Print…。WebView の描画内容を印刷する。
    @objc func printDocument(_ sender: Any?) {
        guard let window, let webView = webViewProxy.webView else { return }
        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let operation = webView.printOperation(with: printInfo)
        // WKWebView の printOperation はビューのフレームが zero のままだと
        // 白紙になるため、印刷対象の用紙サイズを明示する
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Edit > 検索…。プレビュー右上の検索バーを開く。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないため無効化する
    /// (validateMenuItem 側で判定)。
    @objc func find(_ sender: Any?) {
        runFindScript(ViewerBridge.openFindScript)
    }

    /// Edit > 次を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findNext(_ sender: Any?) {
        runFindScript(ViewerBridge.findNextScript)
    }

    /// Edit > 前を検索。検索バーが開いている間のみ JS 側で処理される。
    @objc func findPrevious(_ sender: Any?) {
        runFindScript(ViewerBridge.findPrevScript)
    }

    /// find / findNext / findPrevious 共通のガードと JS 実行。
    /// HTML ファイルの直接ロード表示中は viewer.html の JS が存在しないためスキップする。
    private func runFindScript(_ script: String) {
        guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
        webView.evaluateJavaScript(script)
    }

    /// View > Toggle Line Numbers / ツールバーの行番号ボタン。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        store.showLineNumbers.toggle()
        updateLineNumbersToolbarItem()
    }

    /// View メニュー > ソース表示トグル。レンダリング表示とソース表示を切り替える。
    @objc func toggleSourceView(_ sender: Any?) {
        setSourceMode(!isSourceMode)
    }

    /// View > Back。ファイル履歴を 1 つ戻る。
    @objc func goBack(_ sender: Any?) {
        navigateHistory(by: -1)
    }

    /// View > Forward。ファイル履歴を 1 つ進む。
    @objc func goForward(_ sender: Any?) {
        navigateHistory(by: 1)
    }

    /// モード切替セグメントコントロールの選択変更を受けて呼ばれる。
    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        setSourceMode(sender.selectedSegment == ModeSegment.source.rawValue)
    }

    /// isSourceMode を変更し、store・永続化・モード切替セグメントの表示更新までを一貫して行う。
    private func setSourceMode(_ newValue: Bool) {
        // モードを書き換える前に、切替元モードのスクロール位置を確定保存する
        // (performFileSwitch と同じ理由。切替後に保存すると入場側モードのキーへ誤って保存される)。
        if newValue != isSourceMode {
            saveCurrentScrollPosition(for: fileURL, mode: isSourceMode ? .source : .rendered)
        }
        applySourceMode(newValue)
        sourceModeStore.setSourceMode(isSourceMode, for: fileURL)
    }

    /// isSourceMode を変更し、store への反映とモード切替セグメントの表示更新までを一貫して行う。
    /// isSourceMode の変更が store 経由で SwiftUI の更新サイクルをトリガーし、
    /// ViewerWebView.updateNSView → updateContent が呼ばれ、
    /// 自動的にモード切替(必要なら再描画)が行われる。
    private func applySourceMode(_ newValue: Bool) {
        if isSourceMode != newValue {
            isSourceMode = newValue
            store.isSourceMode = newValue
        }
        updateModeToggleAppearance()
        updateLineNumbersToolbarItem()
    }

    /// モード切替セグメントの選択状態・有効/無効を現在のファイル種別に合わせて更新する。
    /// プレビューできない種別(.code)ではソース側を、テキストソースを持たない
    /// バイナリ種別(画像・PDF)ではプレビュー側を、それぞれ選択済み・唯一の有効状態にする。
    /// - Parameter item: 更新対象のツールバーアイテム。省略時は window.toolbar から検索する
    ///   (生成中でまだ toolbar.items に含まれないアイテムを更新する場合は明示的に渡すこと)。
    private func updateModeToggleAppearance(_ item: NSToolbarItem? = nil) {
        guard let item = item ?? window?.toolbar?.items.first(where: {
            $0.itemIdentifier == Self.modeToggleItemIdentifier
        }), let segmentedControl = item.view as? NSSegmentedControl else { return }
        let isEnabled = !store.isUnsupported
        segmentedControl.setEnabled(
            store.fileType.isRenderable && isEnabled, forSegment: ModeSegment.preview.rawValue
        )
        segmentedControl.setEnabled(
            !store.fileType.isBinaryContent && isEnabled, forSegment: ModeSegment.source.rawValue
        )
        segmentedControl.selectedSegment = (store.showsCodeContent ? ModeSegment.source : ModeSegment.preview).rawValue
    }

    /// ファイル切り替え時にソース表示状態をレンダリング表示にリセットする。
    private func resetSourceMode() {
        applySourceMode(false)
    }

    /// ソース表示トグルを有効にできるか。レンダリング可能な形式でも、
    /// サイズ超過などで非対応表示になっている間は切り替え先が不可視なため無効にする。
    var canToggleSourceMode: Bool {
        store.fileType.supportsSourceMode && !store.isUnsupported
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.title = isSourceMode
                ? String(localized: "menu.view.showRendered", bundle: .l10n)
                : String(localized: "menu.view.toggleSource", bundle: .l10n)
            return canToggleSourceMode
        }
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.title = store.showLineNumbers
                ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
                : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
            return store.showsCodeContent
        }
        if menuItem.action == #selector(goBack(_:)) {
            return fileListModel.canGoBack
        }
        if menuItem.action == #selector(goForward(_:)) {
            return fileListModel.canGoForward
        }
        let findActions: [Selector] = [#selector(find(_:)), #selector(findNext(_:)), #selector(findPrevious(_:))]
        if let action = menuItem.action, findActions.contains(action) {
            return !webViewProxy.isDirectHTMLMode
        }
        return true
    }

    /// 二本指スワイプ(トラックパッド)によるファイル履歴の戻る/進むを検知する。
    /// .began でリセットし、.changed で水平・垂直デルタを積算し、.ended で
    /// 積算値をしきい値判定する(単一フレームの .ended デルタはほぼ0になるため)。
    /// 垂直デルタも積算するのは、縦スクロール中の横ドリフト蓄積による誤発火を
    /// 防ぐため(横優勢のときのみナビゲーションする、SwipeHistoryNavigation 側で判定)。
    private func handleScrollWheelForHistorySwipe(_ event: NSEvent) {
        guard event.window === window else { return }
        switch event.phase {
        case .began:
            swipeHorizontalAccumulator = 0
            swipeVerticalAccumulator = 0
        case .changed:
            swipeHorizontalAccumulator += event.scrollingDeltaX
            swipeVerticalAccumulator += event.scrollingDeltaY
        case .ended:
            defer {
                swipeHorizontalAccumulator = 0
                swipeVerticalAccumulator = 0
            }
            guard let offset = SwipeHistoryNavigation.offset(
                forHorizontalDelta: swipeHorizontalAccumulator,
                verticalDelta: swipeVerticalAccumulator,
                threshold: Self.swipeThreshold
            ) else { return }
            navigateHistory(by: offset)
        default:
            break
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
            self.scrollEventMonitor = nil
        }
        saveWindowFrame()
        store.close()
        delegate?.viewerWindowWillClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // ディレクトリ監視はしていないため、キーになったタイミングで一覧を取り直し、
        // 他所で作成/削除されたファイルをサイドバーへ反映する。
        sidebar.refreshFileList()
        delegate?.viewerWindowDidBecomeKey(self)
    }

    /// リサイズ完了時にのみ保存する。ライブリサイズ中は windowDidResize が毎フレーム
    /// 飛ぶため、そこでは保存せず UserDefaults への連打を避ける。
    /// ドラッグ移動やタイリングでの位置変更は windowWillClose 時にまとめて保存される。
    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame()
    }
}

// MARK: - NSToolbarDelegate

extension ViewerWindowController: NSToolbarDelegate {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.backItemIdentifier || itemIdentifier == Self.forwardItemIdentifier {
            return makeHistoryToolbarItem(itemIdentifier)
        }
        if itemIdentifier == Self.lineNumbersItemIdentifier {
            return makeLineNumbersToolbarItem()
        }
        guard itemIdentifier == Self.modeToggleItemIdentifier else { return nil }
        let previewLabel = String(localized: "toolbar.mode.preview", bundle: .l10n)
        let sourceLabel = String(localized: "toolbar.mode.source", bundle: .l10n)
        // ラベル文字列は状態に関わらず固定なので、セグメント幅が切替でジッターしない。
        let segmentedControl = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: previewLabel)!,
                NSImage(
                    systemSymbolName: "chevron.left.forwardslash.chevron.right",
                    accessibilityDescription: sourceLabel
                )!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeSegmentChanged(_:))
        )
        segmentedControl.setToolTip(previewLabel, forSegment: ModeSegment.preview.rawValue)
        segmentedControl.setToolTip(sourceLabel, forSegment: ModeSegment.source.rawValue)

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = String(localized: "toolbar.mode.group", bundle: .l10n)
        item.view = segmentedControl
        updateModeToggleAppearance(item)
        return item
    }

    /// 戻る/進むのツールバーアイテムを生成する。生成時点の履歴状態を初期反映する。
    private func makeHistoryToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let isBack = identifier == Self.backItemIdentifier
        let label = isBack
            ? String(localized: "toolbar.back", bundle: .l10n)
            : String(localized: "toolbar.forward", bundle: .l10n)
        let button = HistoryButtonView(
            systemImage: isBack ? "chevron.left" : "chevron.right",
            accessibilityLabel: label,
            primaryOffset: isBack ? -1 : 1,
            onNavigate: { [weak self] offset in self?.navigateHistory(by: offset) }
        )
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.view = button
        // ウィンドウが狭まりオーバーフロー(») メニューに収容される際、view ベースの
        // アイテムは menuFormRepresentation が無いと action の無い死んだ項目になるため設定する。
        let menuItem = NSMenuItem(
            title: label,
            action: isBack
                ? #selector(goBack(_:)) : #selector(goForward(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        updateHistoryToolbarItem(item)
        return item
    }

    /// 戻る/進むアイテム 1 つへ現在の履歴状態を反映する。
    private func updateHistoryToolbarItem(_ item: NSToolbarItem) {
        guard let button = item.view as? HistoryButtonView else { return }
        if item.itemIdentifier == Self.backItemIdentifier {
            button.updateState(isEnabled: fileListModel.canGoBack, entries: fileListModel.backHistory)
        } else {
            button.updateState(isEnabled: fileListModel.canGoForward, entries: fileListModel.forwardHistory)
        }
    }

    /// 行番号トグルのツールバーアイテムを生成する。常時表示し、
    /// コード系コンテンツ表示中(showsCodeContent)以外は無効にする。
    private func makeLineNumbersToolbarItem() -> NSToolbarItem {
        let label = String(localized: "menu.view.showLineNumbers", bundle: .l10n)
        let button = NSButton(
            image: NSImage(systemSymbolName: "list.number", accessibilityDescription: label)!,
            target: self,
            action: #selector(toggleLineNumbers(_:))
        )
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        let item = NSToolbarItem(itemIdentifier: Self.lineNumbersItemIdentifier)
        item.label = label
        item.view = button
        // ウィンドウが狭まりオーバーフロー(») メニューに収容される際、view ベースの
        // アイテムは menuFormRepresentation が無いと action の無い死んだ項目になるため設定する。
        let menuItem = NSMenuItem(title: label, action: #selector(toggleLineNumbers(_:)), keyEquivalent: "")
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        updateLineNumbersToolbarItem(item)
        return item
    }

    /// 行番号アイテムの有効/無効・オンオフ表示・ツールチップを現在の表示状態に合わせて更新する。
    /// - Parameter item: 更新対象。省略時は window.toolbar から検索する
    ///   (生成中でまだ toolbar.items に含まれないアイテムを更新する場合は明示的に渡すこと)。
    private func updateLineNumbersToolbarItem(_ item: NSToolbarItem? = nil) {
        guard let item = item ?? window?.toolbar?.items.first(where: {
            $0.itemIdentifier == Self.lineNumbersItemIdentifier
        }), let button = item.view as? NSButton else { return }
        button.isEnabled = store.showsCodeContent
        button.state = store.showLineNumbers ? .on : .off
        item.toolTip = store.showLineNumbers
            ? String(localized: "menu.view.hideLineNumbers", bundle: .l10n)
            : String(localized: "menu.view.showLineNumbers", bundle: .l10n)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            .flexibleSpace, Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            Self.backItemIdentifier, Self.forwardItemIdentifier,
            Self.lineNumbersItemIdentifier, Self.modeToggleItemIdentifier,
            .flexibleSpace, .space,
        ]
    }
}
