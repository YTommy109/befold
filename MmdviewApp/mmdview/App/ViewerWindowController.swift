import AppKit
import SwiftUI
import WebKit

/// 1 ファイルに対応する 1 ウィンドウを管理する NSWindowController。
/// SwiftUI の ViewerContentView を NSHostingView 経由で表示する。
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    /// 最後に調整したウィンドウフレーム（位置＋サイズ）の保存キー。全ウィンドウで共有する。
    private static let lastWindowFrameKey = "LastWindowFrame"
    private static let defaultContentSize = NSSize(width: 1100, height: 850)
    private static let sourceToggleItemIdentifier = NSToolbarItem.Identifier("sourceToggle")

    private let defaults: UserDefaults
    private let store: ViewerStore
    private let zoomStore: ZoomStore
    private let webViewProxy = WebViewProxy()
    private(set) var isSourceMode = false
    private(set) var fileURL: URL
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    let fileListModel: FileListModel
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
    /// 切替先ファイルが自分以外のウィンドウで既に開かれているかを問い合わせるコールバック。
    /// true(マネージャが既存ウィンドウを前面化済み)なら switchFile は切替を中止する。
    var isFileOpenInAnotherWindow: ((_ url: URL) -> Bool)?

    // MARK: - Initialization

    init(fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.defaults = defaults
        store = ViewerStore()
        let files = DirectoryLister.listFiles(in: fileURL.deletingLastPathComponent())
        fileListModel = FileListModel(
            files: files,
            selection: Self.listEntry(for: fileURL, in: files)
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

        store.onFileRenamed = { [weak self] newURL in
            self?.handleRename(to: newURL)
        }
        store.openFile(fileURL)
        updateToolbarVisibility()
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView)を並べる split view controller を組み立てる。
    private func makeSplitViewController() -> NSViewController {
        let contentView = ViewerContentView(
            store: store,
            initialZoom: zoomStore.zoom(for: fileURL),
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: fileURL)
            },
            webViewProxy: webViewProxy
        )
        let fileListView = FileListView(
            model: fileListModel,
            onSelect: { [weak self] url in self?.switchFile(to: url) }
        )
        return ViewerSplitViewController(sidebar: fileListView, content: contentView)
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
        // (例: .md → .swift)ソース表示トグルが成立しなくなる場合のみリセットする。
        if isSourceMode, !FileType(url: newURL).isRenderable {
            resetSourceMode()
        }
        updateToolbarVisibility()
        // init 時のスナップショットのままだとサイドバーに旧名が残るため、再取得して選択し直す。
        refreshFileList()
        onRename?(oldURL, newURL)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL != oldURL else { return }
        // 「1 ファイル 1 ウィンドウ」不変条件: 切替先が別ウィンドウで開かれている場合は
        // そのウィンドウを前面化(マネージャ側)して切替を中止し、サイドバー選択を元へ戻す。
        if isFileOpenInAnotherWindow?(newURL) == true {
            fileListModel.selection = oldURL
            return
        }
        // 内容差し替え前にビューモードをレンダリング表示へ戻し、旧内容の無駄な再描画を避ける。
        resetSourceMode()
        applyURLToWindow(newURL)
        store.openFile(newURL)
        updateToolbarVisibility()
        // 切替はリネームではない。旧ファイルの倍率は保存済みのまま保持し、
        // 新ファイルは自身の保存倍率(なければデフォルト)で表示する。
        applyStoredZoomToWebView()
        fileListModel.selection = newURL
        onSwitchFile?(oldURL, newURL)
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

    /// サイドバーのファイル一覧を現在のディレクトリで取り直し、現在ファイルを選択する。
    private func refreshFileList() {
        let files = DirectoryLister.listFiles(in: fileURL.deletingLastPathComponent())
        fileListModel.files = files
        let selected = Self.listEntry(for: fileURL, in: files)
        if fileListModel.selection != selected {
            fileListModel.selection = selected
        }
    }

    /// 一覧内で url と同じファイルを指す URL を返す。List の選択一致は URL の
    /// 同値性に依存するため、シンボリックリンク解決の有無で表記が揺れても
    /// 一致するよう正規化キーで照合する。見つからなければ url をそのまま返す。
    private static func listEntry(for url: URL, in files: [URL]) -> URL {
        let key = url.normalizedPathKey
        return files.first { $0.normalizedPathKey == key } ?? url
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

    // MARK: - Frame Persistence

    /// 現在のウィンドウフレーム（位置＋サイズ）を保存する。
    /// フルスクリーン中のフレームは通常ウィンドウの寸法として無意味なため保存しない。
    private func saveWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        defaults.set(window.frameDescriptor, forKey: Self.lastWindowFrameKey)
    }

    // MARK: - Menu Actions

    /// View > Zoom In。WebView 内の JS ズーム実装を呼び出す。
    @objc func zoomIn(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.zoomInScript)
    }

    /// View > Zoom Out。
    @objc func zoomOut(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.zoomOutScript)
    }

    /// View > Actual Size。倍率を 100% に戻す。
    @objc func resetZoom(_ sender: Any?) {
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.zoomResetScript)
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

    /// Toolbar > ソース表示トグル。レンダリング表示とソース表示を切り替える。
    @objc func toggleSourceView(_ sender: Any?) {
        isSourceMode.toggle()
        let mode: ViewerBridge.ViewMode = isSourceMode ? .source : .rendered
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(mode))
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
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(.rendered))
        updateSourceToggleAppearance()
    }

    /// ツールバーの再バリデーションを要求する。トグルボタンの enabled 状態は
    /// validateToolbarItem(_:) が現在のファイル種別から決める。
    private func updateToolbarVisibility() {
        window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Menu Validation

    /// ソース表示トグルを有効にできるか。レンダリング可能な形式でも、
    /// サイズ超過などで非対応表示になっている間は切り替え先が不可視なため無効にする。
    var canToggleSourceMode: Bool {
        store.fileType.isRenderable && !store.isUnsupported
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.title = isSourceMode
                ? String(localized: "menu.view.showRendered", bundle: .l10n)
                : String(localized: "menu.view.toggleSource", bundle: .l10n)
            return canToggleSourceMode
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        store.close()
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // ディレクトリ監視はしていないため、キーになったタイミングで一覧を取り直し、
        // 他所で作成/削除されたファイルをサイドバーへ反映する。
        refreshFileList()
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
        [.flexibleSpace, Self.sourceToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sourceToggleItemIdentifier, .flexibleSpace, .space]
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
