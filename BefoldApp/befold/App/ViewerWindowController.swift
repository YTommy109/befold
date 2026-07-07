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
    private let forceSidebarVisible: Bool
    private let webViewProxy = WebViewProxy()
    private(set) var isSourceMode = false
    private(set) var fileURL: URL
    /// サイドバーのファイル一覧と選択状態。リネームやキーウィンドウ化に合わせて更新する。
    let fileListModel: FileListModel
    /// このタブの戻る/進むナビゲーション履歴（メモリ内のみ）。
    let history = NavigationHistory()
    /// 戻る/進む適用中は true。この間は recordHistory による再記録を抑止する。
    private var isApplyingHistory = false
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

    init(fileURL: URL, zoomStore: ZoomStore, defaults: UserDefaults = .standard, forceSidebarVisible: Bool = false) {
        self.fileURL = fileURL
        self.zoomStore = zoomStore
        self.defaults = defaults
        self.forceSidebarVisible = forceSidebarVisible
        store = ViewerStore()
        let parentDir = fileURL.deletingLastPathComponent()
        let entries = DirectoryLister.listEntries(in: parentDir, sortOrder: .foldersFirst)
        fileListModel = FileListModel(
            currentDirectory: parentDir,
            entries: entries,
            selection: fileURL
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
        recordHistory()
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView)を並べる split view controller を組み立てる。
    private func makeSplitViewController() -> NSViewController {
        let contentView = ViewerContentView(
            store: store,
            zoomStore: zoomStore,
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
                refreshFileList()
            },
            onOpenInNewWindow: { url in
                AppDelegate.shared?.openViewer(for: url)
            },
            onNavigateHistory: { [weak self] offset in self?.navigateHistory(by: offset) }
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
                showFileNotFoundAlert(path: url.path)
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

    private func showFileNotFoundAlert(path: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "alert.fileNotFound.message",
            defaultValue: "File Not Found",
            bundle: .l10n
        )
        alert.informativeText = path
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
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
        if newDir.standardizedFileURL
            != fileListModel.currentDirectory.standardizedFileURL
        {
            fileListModel.currentDirectory = newDir
        }
        refreshFileList()
        onRename?(oldURL, newURL)
        history.renameOccurred(from: oldURL, to: newURL)
        refreshHistoryState()
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
        let newDir = newURL.deletingLastPathComponent().standardizedFileURL
        if newDir != fileListModel.currentDirectory.standardizedFileURL {
            fileListModel.currentDirectory = newURL.deletingLastPathComponent()
            refreshFileList()
        } else {
            fileListModel.selection = matchingEntryURL(for: newURL)
        }
        onSwitchFile?(oldURL, newURL)
        recordHistory()
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
        var entries = DirectoryLister.listEntries(
            in: fileListModel.currentDirectory,
            sortOrder: fileListModel.sortOrder
        )
        ensureCurrentFile(in: &entries)
        fileListModel.entries = entries
        let matched = matchingEntryURL(for: fileURL)
        if fileListModel.selection != matched {
            fileListModel.selection = matched
        }
    }

    /// エントリ一覧に現在のファイルが含まれていなければ末尾に追加する。
    /// allExtensions に含まれない拡張子(plaintext フォールバック)のファイルが
    /// サイドバーから消える回帰を防ぐ。
    private func ensureCurrentFile(in entries: inout [FileListEntry]) {
        let dir = fileURL.deletingLastPathComponent().standardizedFileURL
        guard dir == fileListModel.currentDirectory.standardizedFileURL else {
            return
        }
        let key = fileURL.normalizedPathKey
        if !entries.contains(where: { $0.url.normalizedPathKey == key }) {
            entries.append(FileListEntry(url: fileURL, kind: .file))
        }
    }

    /// エントリ一覧から URL の正規化キーが一致するものを探し、
    /// 見つからなければ元の URL をそのまま返す。
    private func matchingEntryURL(for url: URL) -> URL {
        let key = url.normalizedPathKey
        return fileListModel.entries.first {
            $0.url.normalizedPathKey == key
        }?.url ?? url
    }

    /// サイドバーで別フォルダーへ移動する。ホームディレクトリ配下のみ許可する。
    func navigateToFolder(_ url: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let target = url.standardizedFileURL
        guard target == home || target.path.hasPrefix(home.path + "/") else { return }
        let previous = fileListModel.currentDirectory
        fileListModel.currentDirectory = url
        fileListModel.entries = DirectoryLister.listEntries(
            in: url, sortOrder: fileListModel.sortOrder
        )
        let isGoingUp = target == previous.deletingLastPathComponent()
            .standardizedFileURL
        if isGoingUp {
            let prevKey = previous.standardizedFileURL.path
            fileListModel.selection = fileListModel.entries.first {
                $0.kind == .folder
                    && $0.url.standardizedFileURL.path == prevKey
            }?.url
            recordHistory()
        } else if let firstFile = fileListModel.entries.first(where: { $0.kind == .file }) {
            switchFile(to: firstFile.url)
        } else {
            fileListModel.selection = nil
            recordHistory()
        }
    }

    // MARK: - Navigation History

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        guard let entry = history.move(by: offset) else { return }
        if !applyHistoryEntry(entry) {
            _ = history.move(by: -offset)
        }
        refreshHistoryState()
    }

    /// 現在の表示状態（ディレクトリ＋ファイル）を履歴に記録する。
    /// 戻る/進む適用中は抑止する。push は現在エントリと同一なら無視する。
    private func recordHistory() {
        guard !isApplyingHistory else { return }
        history.push(HistoryEntry(directory: fileListModel.currentDirectory, file: fileURL))
        refreshHistoryState()
    }

    /// 履歴エントリを表示へ適用する。適用できなかった場合は false を返す。
    /// switchFile を経由せずファイル切替をインラインで行い、
    /// ディレクトリの上書きや二重リストを防ぐ。
    @discardableResult
    private func applyHistoryEntry(_ entry: HistoryEntry) -> Bool {
        // 「1 ファイル 1 ウィンドウ」不変条件の事前チェック
        if let file = entry.file,
           file.normalizedPathKey != fileURL.normalizedPathKey,
           isFileOpenInAnotherWindow?(file) == true
        {
            return false
        }
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        if entry.directory.normalizedPathKey
            != fileListModel.currentDirectory.normalizedPathKey
        {
            fileListModel.currentDirectory = entry.directory
        }
        if let file = entry.file,
           file.normalizedPathKey != fileURL.normalizedPathKey
        {
            let oldURL = fileURL
            resetSourceMode()
            applyURLToWindow(file)
            store.openFile(file)
            updateToolbarVisibility()
            applyStoredZoomToWebView()
            onSwitchFile?(oldURL, file)
        }
        refreshFileList()
        return true
    }

    /// 履歴状態をサイドバー（FileListModel）へ反映する。
    private func refreshHistoryState() {
        fileListModel.backHistory = history.backEntries()
        fileListModel.forwardHistory = history.forwardEntries()
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
            let newZoom = min(ZoomStore.maxZoom, webView.pageZoom + 0.1)
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
            let newZoom = max(ZoomStore.minZoom, webView.pageZoom - 0.1)
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

    /// View > Toggle Line Numbers。行番号表示の有無を切り替える。
    @objc func toggleLineNumbers(_ sender: Any?) {
        store.showLineNumbers.toggle()
    }

    /// Toolbar > ソース表示トグル。レンダリング表示とソース表示を切り替える。
    @objc func toggleSourceView(_ sender: Any?) {
        isSourceMode.toggle()
        store.isSourceMode = isSourceMode
        // HTML はビューモード切替を updateContent 側が担う(rendered は直接ロード、
        // source は viewer.html へ戻して setViewMode)。ここで JS を呼ぶと直後の
        // 再ロードに上書きされる無駄打ちになるため呼ばない。それ以外の形式は
        // content 再描画が走らないため、ここで viewModeScript を直接送って反映する。
        if store.fileType != .html {
            let mode: ViewerBridge.ViewMode = isSourceMode ? .source : .rendered
            webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(mode))
        }
        // HTML 直接ロードモードの場合、isSourceMode の変更が store 経由で
        // SwiftUI の更新サイクルをトリガーし、ViewerWebView.updateNSView →
        // updateContent が呼ばれ、自動的にモード切替が行われる。
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
        if !webViewProxy.isDirectHTMLMode {
            webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(.rendered))
        }
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
        return true
    }

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
