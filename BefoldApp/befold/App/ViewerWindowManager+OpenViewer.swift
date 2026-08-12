import AppKit
import BefoldCLI
import BefoldKit

/// ビューアウィンドウを開く経路。新規ウィンドウの生成と、既に開いているウィンドウの
/// 前面化はどちらもここへ集約する(CLI の表示オプションが効く経路を 1 つに揃えるため)。
extension ViewerWindowManager {
    /// 指定 URL のファイルをビューアウィンドウで開く。
    /// 同じファイルが既に開かれている場合は既存ウィンドウを前面に表示する。
    ///
    /// CLI 由来の表示オーバーライドは `options` ごとそのまま受け取る。呼び出し側で
    /// フィールドを手写しして渡すと、`CLIOpenOptions` にオプションを足したときに
    /// 特定経路(セッション復元など)だけ転送漏れする。
    ///
    /// 戻り値は、この呼び出しが対象としたコントローラ(新規生成、または前面化した既存)。
    /// 開けなかった場合は nil。`controllers` は 1 パスに複数のコントローラを持ちうる
    /// 多重マップなので、呼び出し直後に `window(forPath:)` で引き直すと**別のウィンドウ**を
    /// 掴む(TASK-415)。開いたウィンドウに続けて触る呼び出し元はこの戻り値を使うこと。
    @discardableResult
    func openViewer(
        for url: URL,
        options: CLIOpenOptions = CLIOpenOptions(),
        disposition: OpenDisposition = .currentTab,
        relativeTo sourceWindow: NSWindow? = nil,
        forceSidebarVisible: Bool = false
    ) -> ViewerWindowController? {
        guard fileReader.fileExists(at: url) else {
            // 新規オープン時点ではまだ親ウィンドウが無いため over: nil でモーダル表示する。
            FileNotFoundUI.present(url: url, over: nil)
            return nil
        }

        let key = url.normalizedPathKey
        // Finder/CLI/リンクからの再オープン(.currentTab)は重複ウィンドウを作らず既存を前面化する。
        // (ウィンドウ内のサイドバー切替だけは他ウィンドウを無視して自ウィンドウを切り替える)
        // 一方 .newTab/.newWindow は cmd+クリックやコンテキストメニューでユーザーが
        // 明示的に新規オープンを求めた経路なので、重複抑止より意図を優先して素通しする
        // (既に開いているファイルで「新しいウィンドウで開く」が無反応に見える問題: issue #431)。
        if disposition == .currentTab, let existing = controllers[key]?.first {
            // 表示オプションの適用規則は ViewerDisplayOptionsApplier に一本化してある。
            // 前面化(activate / focusWindow)は開く経路の責務なのでここに残す。
            ViewerDisplayOptionsApplier.apply(
                options, to: existing, forceSidebarVisible: forceSidebarVisible
            )
            NSApp.activate()
            existing.focusWindow()
            return existing
        }

        let controller = makeController(
            for: url, options: options, forceSidebarVisible: forceSidebarVisible
        )
        register(controller, forKey: key)
        controller.delegate = self
        NSApp.activate()
        controller.showWindow(nil)
        // window が nil(生成直後で取得できない等)ならタブ結合をあきらめ独立ウィンドウのまま
        // 表示する(attachAsTab と同じ「開けないよりタブにならない」への縮退)。
        if disposition == .newTab, let window = controller.window {
            ViewerTabGrouping.attachAsTab(window, to: sourceWindow, select: true)
        }
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recentRepositories.recordIfNeeded(for: url, controller: controller)
        return controller
    }

    /// 新規ウィンドウのコントローラを、初期表示状態(サイドバー開閉・ウィンドウ枠)を
    /// 解決したうえで生成する。共有依存の渡し先はここ 1 箇所で、渡し忘れれば
    /// コンパイルが落ちる(既定値を持たない引数として受けている)。
    private func makeController(
        for url: URL, options: CLIOpenOptions, forceSidebarVisible: Bool
    ) -> ViewerWindowController {
        let lastActivePathKey = sessionStore.savedActivePath()
        // 開閉の解決順: CLI の明示指定(--sidebar/--no-sidebar) > フォルダーオープンによる強制表示 > 記憶の引き継ぎ。
        let initialSidebarCollapsed: Bool = if let showSidebar = options.showSidebar {
            !showSidebar
        } else if forceSidebarVisible {
            false
        } else {
            perFileState.sidebar.initialCollapsed(for: url, lastActivePathKey: lastActivePathKey)
        }
        perFileState.sidebar.setCollapsed(initialSidebarCollapsed, for: url)

        let initialFrameDescriptor = perFileState.windowFrame.initialFrameDescriptor(
            for: url, lastActivePathKey: lastActivePathKey
        )
        if let initialFrameDescriptor {
            perFileState.windowFrame.setFrameDescriptor(initialFrameDescriptor, for: url)
        }

        return ViewerWindowController(
            fileURL: url,
            sidebarDisplayPreference: sidebarDisplayPreference,
            diffDisplayPreference: diffDisplayPreference,
            diffLoader: diffLoader,
            findOptionsPreference: findOptionsPreference,
            codeFontPreference: codeFontPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            gitFileIndex: gitFileIndex,
            gitStatusStore: gitStatusStore,
            initialSidebarCollapsed: initialSidebarCollapsed,
            initialFrameDescriptor: initialFrameDescriptor,
            initialSortOrder: options.viewerSortOrder,
            showLineNumbersOverride: options.showLineNumbers,
            sourceModeOverride: options.sourceMode,
            store: makeStore?(url),
            makeContentView: makeContentView,
            openFileElsewhere: { [weak self] fileURL, disposition, sourceWindow in
                self?.openViewer(for: fileURL, disposition: disposition, relativeTo: sourceWindow)
            }
        )
    }
}
