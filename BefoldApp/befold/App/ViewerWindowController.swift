import AppKit
import SwiftUI
import WebKit

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController {
    /// 最後に調整したウィンドウフレーム（位置＋サイズ）の保存キー。全ウィンドウで共有する。
    private static let lastWindowFrameKey = "LastWindowFrame"
    private static let defaultContentSize = NSSize(width: 1100, height: 850)
    private static let sourceToggleItemIdentifier = NSToolbarItem.Identifier("sourceToggle")

    private let defaults: UserDefaults
    private let store: ViewerStore
    private let zoomStore: ZoomStore
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

    /// ウィンドウが閉じられたときに呼ばれるコールバック。ViewerWindowManager がウィンドウ管理辞書から除去するために使用する。
    var onClose: (() -> Void)?
    /// 開いているファイルが rename / move されたときに旧 URL・新 URL を通知するコールバック。
    /// ViewerWindowManager がウィンドウ管理辞書のキー付け替えとセッション記録の更新に使用する。
    var onRename: ((_ old: URL, _ new: URL) -> Void)?
    /// ウィンドウがキーウィンドウになったときに呼ばれるコールバック。
    /// ViewerWindowManager がアクティブファイルのセッション記録の更新に使用する。
    var onBecomeKey: (() -> Void)?
    /// switchFile(to:) でファイルを切り替えたときに旧 URL・新 URL を通知するコールバック。
    var onSwitchFile: ((_ old: URL, _ new: URL) -> Void)?
    /// サイドバーのアイコンボタンから不可視ファイル表示切替が要求されたときに呼ばれるコールバック。
    /// ViewerWindowManager が toggleHiddenFiles() を束ねるために使用する。
    var onToggleHiddenFiles: (() -> Void)?
    /// 指定 URL が自分以外のウィンドウで既に開かれているかを判定する純粋チェック。
    var isFileOpenInAnotherWindow: ((_ url: URL) -> Bool)?
    /// 指定 URL を開いている別ウィンドウを前面化する。switchFile で使用。
    var focusWindowForFile: ((_ url: URL) -> Void)?

    // MARK: - Initialization

    /// - Parameter hiddenFilesPreference: 本番では必ず AppDelegate → ViewerWindowManager から
    ///   注入される単一の共有インスタンスを渡すこと。デフォルト値は、不可視ファイル挙動に
    ///   無関心なテストが省略できるようにするためのもの。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    init(
        fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard,
        hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        forceSidebarVisible: Bool = false
    ) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
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
        store.openFile(fileURL)
        updateToolbarVisibility()
        sidebar.recordHistory()
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView)を並べる split view controller を組み立てる。
    private func makeSplitViewController() -> NSViewController {
        let contentView = ViewerContentView(
            store: store,
            zoomStore: zoomStore,
            findOptionsPreference: findOptionsPreference,
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: fileURL)
            },
            onOpenReference: { [weak self] href, isExternal, newWindow in
                self?.handleOpenReference(href: href, isExternal: isExternal, newWindow: newWindow)
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
            onNavigateHistory: { [weak self] offset in self?.navigateHistory(by: offset) },
            onToggleHiddenFiles: { [weak self] in self?.onToggleHiddenFiles?() }
        )
        return ViewerSplitViewController(
            sidebar: fileListView,
            content: contentView,
            forceSidebarVisible: forceSidebarVisible
        )
    }

    /// cmd+click によるリンク/パス参照のアクティベーションを処理する。
    private func handleOpenReference(href: String, isExternal: Bool, newWindow: Bool) {
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
        guard newURL != oldURL else { return }
        applyURLToWindow(newURL)

        // 実体は同じファイルなので旧パスの倍率を新パスへ引き継ぐ(旧パスはもう存在しない)。
        zoomStore.migrateZoom(from: oldURL, to: newURL)
        // 内容は不変なのでビューモードは維持する。ただし対応形式が変わり
        // (例: .md → .swift、.md → .png)ソース表示トグルが成立しなくなる
        // 場合のみリセットする。
        if isSourceMode, !FileType(url: newURL).supportsSourceMode {
            resetSourceMode()
        }
        updateToolbarVisibility()
        let newDir = newURL.deletingLastPathComponent()
        if newDir.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        {
            fileListModel.currentDirectory = newDir
        }
        sidebar.refreshFileList()
        onRename?(oldURL, newURL)
        sidebar.applyRename(from: oldURL, to: newURL)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    /// ファイル切替の実処理のみ担い、選択同期・履歴記録は SidebarNavigator へ委譲する。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL != oldURL else { return }
        if isFileOpenInAnotherWindow?(newURL) == true {
            focusWindowForFile?(newURL)
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
    /// ビューモードのリセット、URL 更新、コンテンツ読込、ズーム適用、コールバック通知を行う。
    /// 切替先が存在しない場合はアラートを表示して false を返す(状態は変更しない)。
    @discardableResult
    func performFileSwitch(to newURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: newURL.path) else {
            showFileNotFoundAlert(url: newURL)
            return false
        }
        let oldURL = fileURL
        resetSourceMode()
        applyURLToWindow(newURL)
        store.openFile(newURL)
        updateToolbarVisibility()
        applyStoredZoomToWebView()
        onSwitchFile?(oldURL, newURL)
        return true
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
        isFileOpenInAnotherWindow?(url) == true
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

    /// View > Zoom In。HTML 直接ロード時は WKWebView の pageZoom を、それ以外は JS ズーム実装を使う。
    @objc func zoomIn(_ sender: Any?) {
        guard let webView = webViewProxy.webView else { return }
        if webViewProxy.isDirectHTMLMode {
            let newZoom = min(ZoomStore.maxZoom, webView.pageZoom + ZoomStore.zoomStep)
            webView.pageZoom = newZoom
            zoomStore.setZoom(newZoom, for: fileURL)
        } else {
            webView.evaluateJavaScript(ViewerBridge.zoomInScript)
        }
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        guard let webView = webViewProxy.webView else { return }
        if webViewProxy.isDirectHTMLMode {
            let newZoom = max(ZoomStore.minZoom, webView.pageZoom - ZoomStore.zoomStep)
            webView.pageZoom = newZoom
            zoomStore.setZoom(newZoom, for: fileURL)
        } else {
            webView.evaluateJavaScript(ViewerBridge.zoomOutScript)
        }
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        guard let webView = webViewProxy.webView else { return }
        if webViewProxy.isDirectHTMLMode {
            webView.pageZoom = ZoomStore.defaultZoom
            zoomStore.setZoom(ZoomStore.defaultZoom, for: fileURL)
        } else {
            webView.evaluateJavaScript(ViewerBridge.zoomResetScript)
        }
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

    /// View > Toggle Line Numbers。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        store.showLineNumbers.toggle()
    }

    /// Toolbar > ソース表示トグル。レンダリング表示とソース表示を切り替える。
    @objc func toggleSourceView(_ sender: Any?) {
        isSourceMode.toggle()
        store.isSourceMode = isSourceMode
        // isSourceMode の変更が store 経由で SwiftUI の更新サイクルをトリガーし、
        // ViewerWebView.updateNSView → updateContent が呼ばれ、
        // 自動的にモード切替(必要なら再描画)が行われる。
        updateSourceToggleAppearance()
    }

    /// トグルボタンの見た目(アイコン・ツールチップ)を現在のモードに合わせて更新する。
    private func updateSourceToggleAppearance(_ item: NSToolbarItem? = nil) {
        guard let item = item ?? window?.toolbar?.items.first(where: {
            $0.itemIdentifier == Self.sourceToggleItemIdentifier
        }) else { return }
        // ソース表示中はレンダリング表示へ戻すボタン、レンダリング表示中はソースを表示するボタン。
        // ラベルはメニュー項目と同じローカライズ文字列を共有する。
        let symbolName = isSourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right"
        let label = isSourceMode
            ? String(localized: "menu.view.showRendered", bundle: .l10n)
            : String(localized: "menu.view.toggleSource", bundle: .l10n)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
    }

    /// ファイル切り替え時にソース表示状態をレンダリング表示にリセットする。
    private func resetSourceMode() {
        guard isSourceMode else { return }
        isSourceMode = false
        store.isSourceMode = false
        updateSourceToggleAppearance()
    }

    /// ツールバーの再バリデーションを要求する。トグルボタンの enabled 状態は
    /// validateToolbarItem(_:) が現在のファイル種別から決める。
    private func updateToolbarVisibility() {
        window?.toolbar?.validateVisibleItems()
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
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // ディレクトリ監視はしていないため、キーになったタイミングで一覧を取り直し、
        // 他所で作成/削除されたファイルをサイドバーへ反映する。
        sidebar.refreshFileList()
        onBecomeKey?()
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
        guard itemIdentifier == Self.sourceToggleItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = String(localized: "menu.view.toggleSource", bundle: .l10n)
        item.isBordered = true
        item.target = self
        item.action = #selector(toggleSourceView(_:))
        updateSourceToggleAppearance(item)
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .flexibleSpace, Self.sourceToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, Self.sourceToggleItemIdentifier, .flexibleSpace, .space]
    }
}

// MARK: - NSToolbarItemValidation

extension ViewerWindowController: NSToolbarItemValidation {
    /// NSToolbar の自動バリデーションはターゲットがアクションに応答する限り
    /// isEnabled を true に戻すため、手動で isEnabled を設定しても維持されない。
    /// 唯一有効な制御点であるこのメソッドでファイル種別から enabled を決める。
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard item.itemIdentifier == Self.sourceToggleItemIdentifier else { return true }
        return canToggleSourceMode
    }
}
