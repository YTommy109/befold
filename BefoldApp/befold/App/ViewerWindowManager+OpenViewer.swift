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
            presentFileNotFound(url, removeBookmarkAction(for: url))
            return nil
        }

        let key = url.normalizedPathKey
        // 既存ウィンドウを再利用できる条件は disposition ごとに reusableController が決める。
        // 再利用時の前面化・タブ選択・表示オプション適用はこの 1 ブロックへ集約する。
        if let existing = reusableController(
            forKey: key, disposition: disposition, relativeTo: sourceWindow
        ) {
            // 表示オプションの適用規則は ViewerDisplayOptionsApplier に一本化してある。
            // 前面化(activate / focusWindow)は開く経路の責務なのでここに残す。
            ViewerDisplayOptionsApplier.apply(
                options, to: existing, forceSidebarVisible: forceSidebarVisible
            )
            NSApp.activate()
            existing.focusWindow()
            if let window = existing.window {
                ViewerTabGrouping.selectTab(window)
            }
            return existing
        }

        // 起点の窓が同じフォルダを列挙済みなら、その結果を新しい窓の出発点にする
        // (TASK-532)。disposition では絞らない——新規タブでも新規ウィンドウでも、
        // 同じ一覧を出すなら空から作り直す理由が無い。
        let controller = makeController(
            for: url, options: options, forceSidebarVisible: forceSidebarVisible,
            initialListing: listingSeed(from: sourceWindow)
        )
        register(controller, forKey: key)
        controller.delegate = sessionSync
        NSApp.activate()
        // タブ結合と表示の順序は ViewerTabGrouping.present が持つ(先に表示すると
        // タブへ畳まれる中間状態が 1 フレーム見える: TASK-529)。
        ViewerTabGrouping.present(
            controller.window, asTabOf: disposition == .newTab ? sourceWindow : nil, select: true
        ) {
            controller.showWindow(nil)
        }
        sessionStore.noteOpened(url)
        recentDocumentsStore.noteOpened(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recentRepositories.recordIfNeeded(for: url, controller: controller)
        return controller
    }

    /// 同じファイルを表示中の既存コントローラを再利用できるなら返す(nil なら新規に開く)。
    ///
    /// - `.currentTab`: Finder/CLI/リンクからの再オープン。どのウィンドウで開いていても
    ///   既存を前面化する(ウィンドウ内のサイドバー切替だけは openViewer を通らず
    ///   自ウィンドウを切り替える)。
    /// - `.newTab`: cmd+クリック等。起点ウィンドウと同じタブグループに同じファイルの
    ///   タブが既にあればそれを選択し、重複タブを作らない(TASK-487)。別ウィンドウで
    ///   開いているだけなら素通しし、起点のタブグループへ新しいタブを開く。
    /// - `.newWindow`: ユーザーが明示的に新規ウィンドウを求めた経路なので常に素通しする
    ///   (既に開いているファイルで「新しいウィンドウで開く」が無反応に見える問題: issue #431)。
    private func reusableController(
        forKey key: String, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?
    ) -> ViewerWindowController? {
        switch disposition {
        case .currentTab:
            return controllers[key]?.first
        case .newTab:
            guard let sourceWindow else { return nil }
            let siblings = ViewerTabGrouping.tabWindows(of: sourceWindow)
            return controllers[key]?.first { controller in
                guard let window = controller.window else { return false }
                return siblings.contains(window)
            }
        case .newWindow:
            return nil
        }
    }

    /// 見つからなかったファイルがブックマーク済みなら、それを外す操作を返す(でなければ nil)。
    /// ブックマークは「該当ファイルを開いてトグルオフする」でしか外せないため、開けなくなった
    /// ファイルはこの経路が唯一の個別の外し口になる(issue #485)。
    private func removeBookmarkAction(for url: URL) -> (() -> Void)? {
        guard bookmarkStore.isBookmarked(url) else { return nil }
        return { [bookmarkStore] in bookmarkStore.remove(url) }
    }

    /// 新規ウィンドウのコントローラを、初期表示状態(サイドバー開閉・ウィンドウ枠)を
    /// 解決したうえで生成する。共有依存の渡し先はここ 1 箇所で、渡し忘れれば
    /// コンパイルが落ちる(既定値を持たない引数として受けている)。
    /// 起点ウィンドウのサイドバーが列挙済みの一覧(引き継ぎの材料)。
    /// ビューアウィンドウでない・まだ一覧が届いていないなら nil。
    private func listingSeed(from sourceWindow: NSWindow?) -> SidebarListingSeed? {
        guard let controller = sourceWindow?.windowController as? ViewerWindowController,
              controller.fileListModel.hasLoadedEntries
        else { return nil }
        let model = controller.fileListModel
        return SidebarListingSeed(
            directory: model.entriesDirectory,
            listing: controller.sidebar.lastListing,
            sortOrder: model.sortOrder,
            showHiddenFiles: model.showHiddenFiles
        )
    }

    private func makeController(
        for url: URL, options: CLIOpenOptions, forceSidebarVisible: Bool,
        initialListing: SidebarListingSeed?
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
            displayDefaults: displayDefaults,
            diffDisplayPreference: diffDisplayPreference,
            diffLoader: diffLoader,
            findOptionsPreference: findOptionsPreference,
            headingJumpLevelDefaults: headingJumpLevelDefaults,
            codeFontPreference: codeFontPreference,
            csvNumberFormatPreference: csvNumberFormatPreference,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            gitFileIndex: gitFileIndex,
            gitStatusStore: gitStatusStore,
            initialSidebarCollapsed: initialSidebarCollapsed,
            initialFrameDescriptor: initialFrameDescriptor,
            initialSortOrder: options.sortOrder != nil ? options.viewerSortOrder : nil,
            initialShowHiddenFiles: options.showHiddenFiles,
            initialListing: initialListing,
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
