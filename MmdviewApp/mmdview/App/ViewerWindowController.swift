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
    private var isSourceMode = false
    private(set) var fileURL: URL
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

    // MARK: - Initialization

    init(fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.defaults = defaults
        store = ViewerStore()

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

        let contentView = ViewerContentView(
            store: store,
            initialZoom: zoomStore.zoom(for: fileURL),
            // 現在の fileURL は rename で書き換わるため、旧値を捕捉せず self 経由で参照する
            onZoomChanged: { [weak self] zoom in
                guard let self else { return }
                zoomStore.setZoom(zoom, for: self.fileURL)
            },
            webViewProxy: webViewProxy
        )
        let files = DirectoryLister.listFiles(in: fileURL.deletingLastPathComponent())
        let fileListView = FileListView(
            files: files,
            initialSelection: fileURL,
            onSelect: { [weak self] url in self?.switchFile(to: url) }
        )
        let splitVC = ViewerSplitViewController(sidebar: fileListView, content: contentView)
        // contentViewController の設定でウィンドウがビューのフィッティングサイズに
        // リサイズされるため、フレームの確定はその後に行う。
        // frameDescriptor はフレーム座標系で保存・復元されるため、
        // タイトルバー高さの混入によるサイズのずれは起きない
        window.contentViewController = splitVC
        if let descriptor = defaults.string(forKey: Self.lastWindowFrameKey) {
            window.setFrame(from: descriptor)
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

    /// ファイルの rename / move をウィンドウに反映する。
    private func handleRename(to newURL: URL) {
        let oldURL = fileURL
        guard newURL != oldURL else { return }
        fileURL = newURL

        if let window {
            window.title = newURL.lastPathComponent
            window.representedURL = newURL
        }

        zoomStore.migrateZoom(from: oldURL, to: newURL)
        onRename?(oldURL, newURL)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL != oldURL else { return }
        fileURL = newURL
        store.openFile(newURL)

        if let window {
            window.title = newURL.lastPathComponent
            window.representedURL = newURL
        }

        zoomStore.migrateZoom(from: oldURL, to: newURL)
        resetSourceMode()
        updateToolbarVisibility()
        onSwitchFile?(oldURL, newURL)
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
    private func updateSourceToggleAppearance() {
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: { $0.itemIdentifier == Self.sourceToggleItemIdentifier })
        else { return }
        if isSourceMode {
            item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Rendered")
            item.toolTip = "Toggle rendered view"
        } else {
            item.image = NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: "Source"
            )
            item.toolTip = "Toggle source view"
        }
    }

    /// ファイル切り替え時にソース表示状態をレンダリング表示にリセットする。
    private func resetSourceMode() {
        isSourceMode = false
        updateSourceToggleAppearance()
    }

    /// レンダリング不可なファイルではトグルボタンを無効化する。
    private func updateToolbarVisibility() {
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: { $0.itemIdentifier == Self.sourceToggleItemIdentifier })
        else { return }
        item.isEnabled = store.fileType.isRenderable
    }

    // MARK: - Menu Validation

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.title = isSourceMode
                ? String(localized: "menu.view.showRendered", bundle: .l10n)
                : String(localized: "menu.view.toggleSource", bundle: .l10n)
            return store.fileType.isRenderable
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
        onBecomeKey?()
    }

    /// ライブリサイズだけでなく、ズーム(タイトルバーのダブルクリック等)・
    /// 画面タイリング・プログラムからの変更も含めて捕捉するため、
    /// didResize / didMove の両方で保存する。
    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
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
        item.label = "Source"
        item.toolTip = "Toggle source view"
        item.isBordered = true
        item.image = NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Source"
        )
        item.target = self
        item.action = #selector(toggleSourceView(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sourceToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sourceToggleItemIdentifier, .flexibleSpace, .space]
    }
}
