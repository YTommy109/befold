import AppKit
import BefoldKit
import SwiftUI

// MARK: - Window Assembly

/// ウィンドウ生成時の組み立てと配線——分割ビューの構築・サイドバーナビゲータの生成・
/// WebView コマンドの生成・ストア購読・スワイプ監視——を受け持つ。
///
/// ここに置くのは「init の各工程の中身」であり、**工程どうしの順序制約は init 側に残す**。
/// init から見て 1 行になるものだけを移し、ここに来た関数はどれも
/// 「呼ばれた時点の状態だけを見て 1 つの部品を作る / 1 本の配線を張る」形にしてある。
/// 順序に意味のある処理をここで束ねない(束ねると init から順序が見えなくなる)。
@MainActor
extension ViewerWindowController {
    /// サイドバーへ渡す git 状態の取得クロージャを作る。
    ///
    /// ロジック自体は常時ビルドし、露出点だけを囲う(無効時は機能を消すのではなく空を返す)。
    /// git ステータス系の露出点はここを含めて 3 箇所あり、一覧は FeatureGate の宣言にある。
    /// stable 昇格(TASK-187)ではこの guard を消して常に store を引く形にすればよい。
    static func makeSidebarGitStatusLoader(
        _ store: GitStatusStore
    ) -> (URL, GitStatusRefreshPolicy) async -> GitStatusResult {
        guard FeatureGate.isSidebarGitStatusEnabled else { return { _, _ in .empty } }
        return { directory, policy in await store.statuses(forDirectoryAt: directory, policy: policy) }
    }

    /// サイドバー(一覧・選択同期・フォルダ移動)のナビゲータを作る。
    /// `super.init` より前に呼ぶ必要があるため static にしてある。
    static func makeSidebarNavigator(
        fileURL: URL,
        sidebarDisplayPreference: SidebarDisplayPreference,
        sortOrder: SortOrder,
        gitFileIndex: any GitFileIndexing,
        gitStatusStore: GitStatusStore
    ) -> SidebarNavigator {
        // 初期一覧は空で始め、attach 直後の refreshFileList()(非同期の DirectoryLister.listEntriesAsync)に
        // 埋めさせる。ウィンドウ生成時だけ同期列挙する経路を持たないことで、ネットワーク
        // ボリューム上のフォルダでもウィンドウ表示がディレクトリ列挙を待たない。
        SidebarNavigator(
            currentDirectory: fileURL.deletingLastPathComponent(), entries: [], selection: fileURL,
            sidebarDisplayPreference: sidebarDisplayPreference, sortOrder: sortOrder,
            // 未命中時は `git rev-parse` の subprocess を同期で待つため、
            // メインアクターを離して解決する(サイドバーのヘッダー表示のためだけに
            // フォルダ移動のたびメインスレッドを止めないため)。
            resolveGitRoot: { [gitFileIndex] directory in
                await Task.detached { gitFileIndex.repositoryRoot(forDirectoryAt: directory) }.value
            },
            loadGitStatuses: makeSidebarGitStatusLoader(gitStatusStore)
        )
    }

    /// その原点に既に別のビューアウィンドウが居るか。
    ///
    /// `ViewerWindowChrome` は他の窓の存在を知らない設計なので、初期フレームの重なり回避に
    /// 使う判定はここが供給する。「ビューアウィンドウかどうか」を知っているのはこちら側。
    static func isOriginOccupiedByAnotherViewer(excluding window: NSWindow) -> (NSPoint) -> Bool {
        { origin in
            NSApp.windows.contains { other in
                other !== window
                    && other.isVisible
                    && other.windowController is ViewerWindowController
                    && other.frame.origin == origin
            }
        }
    }

    /// WebView 操作系メニューアクション(ズーム・印刷・検索・スクロール位置保存)の実処理を作る。
    /// - Parameter fallbackURL: self が解放済みのときに使う URL(生成時のファイル)。
    func makeWebViewCommands(
        documentRenderer: (any DocumentRendering)?, fallbackURL: URL
    ) -> WebViewCommandController {
        WebViewCommandController(
            // WKWebView と JS の詳細は adapter に閉じる(ADR 0002 段 4)。
            renderer: documentRenderer ?? WebViewDocumentRenderer(webViewProxy: webViewProxy),
            perFileState: perFileState,
            // 現在 URL は rename/switch で書き換わるため、旧値を捕捉せず self 経由で参照する。
            currentURL: { [weak self] in self?.fileURL ?? fallbackURL },
            onZoomChanged: { [weak self] zoom in self?.store.zoom = zoom },
            onScrollPositionSaved: { [weak self] position, url, mode in
                self?.applySavedScrollPositionToLiveValue(position, for: url, mode: mode)
            },
            // 実行可否は capabilities に集約する(ADR 0002)。フォルダー一覧を表示している間も
            // WKWebView は背後に生き続けるため、見えていない文書への操作はここで止まる。
            capabilities: { [weak self] in self?.capabilities ?? .none }
        )
    }

    /// サイドバー(ファイル一覧)とコンテンツ(WebView/フォルダー一覧)を並べる split view controller を組み立てる。
    func makeSplitViewController(contentOverride: (() -> AnyView)?) -> NSViewController {
        let onSelectFile: (URL) -> Void = { [weak self] url in self?.switchFile(to: url) }
        let onNavigateToFolder: (URL) -> Void = { [weak self] url in self?.navigateToFolder(url) }
        let content: AnyView = contentOverride?() ?? AnyView(ViewerContentView(
            store: store,
            findOptionsPreference: findOptionsPreference,
            codeFontFamily: codeFontPreference.fontFamily,
            codeFontSizePoints: codeFontPreference.fontSizePoints,
            fileListModel: fileListModel,
            rendererDelegate: WeakRendererDelegate(self),
            onSelectFile: onSelectFile,
            onNavigateToFolder: onNavigateToFolder,
            webViewProxy: webViewProxy,
            diffDisplayPreference: diffDisplayPreference
        ))
        let splitViewController = ViewerSplitViewController(
            sidebar: makeFileListView(onSelectFile: onSelectFile, onNavigateToFolder: onNavigateToFolder),
            content: content,
            initialCollapsed: initialSidebarCollapsed,
            onCollapsedChange: { [weak self] collapsed in
                guard let self else { return }
                perFileState.sidebar.recordToggle(collapsed, for: fileURL)
            },
            onSidebarDidReveal: { [weak self] in
                self?.fileListModel.focusSidebarTable()
            }
        )
        sidebarCollapsible = splitViewController
        return splitViewController
    }

    /// サイドバーのファイル一覧ビューを組み立てる。
    private func makeFileListView(
        onSelectFile: @escaping (URL) -> Void, onNavigateToFolder: @escaping (URL) -> Void
    ) -> FileListView {
        FileListView(
            model: fileListModel,
            onSelect: onSelectFile,
            onNavigate: onNavigateToFolder,
            onSortOrderChanged: { [weak self] order in
                guard let self else { return }
                fileListModel.sortOrder = order
                sidebar.refreshFileList()
            },
            onOpenElsewhere: { [weak self] url, disposition in
                guard let self else { return }
                openFileElsewhere(url, disposition, window)
            },
            onExpandFolder: { [weak self] entry in
                self?.sidebar.expandFolder(entry.pathKey, at: entry.url)
            },
            onCollapseFolder: { [weak self] entry in
                self?.sidebar.collapseFolder(entry.pathKey)
            },
            onToggleHiddenFiles: { [weak self] in
                guard let self else { return }
                delegate?.viewerWindowDidToggleHiddenFiles(self)
            },
            onToggleChangedFilesOnly: makeChangedFilesOnlyToggle()
        )
    }

    /// サイドバーヘッダーの「変更されたファイルのみ表示」ボタンの動作を作る。
    ///
    /// git ステータスと同じ開発中機能の露出点であり、無効なら nil を返して
    /// ボタン自体を出さない(FileListView 側が nil で非表示にする)。
    private func makeChangedFilesOnlyToggle() -> (() -> Void)? {
        guard FeatureGate.isSidebarGitStatusEnabled else { return nil }
        return { [weak self] in
            guard let self else { return }
            delegate?.viewerWindowDidToggleChangedFilesOnly(self)
        }
    }

    /// 二本指スワイプによるファイル履歴ナビゲーション検知を開始する。
    /// 停止は windowWillClose が行う(`ViewerWindowController+WindowDelegate.swift`)。
    func startSwipeMonitor(on window: NSWindow) {
        swipeMonitor = SwipeHistoryMonitor(window: window) { [weak self] offset in
            self?.navigateHistory(by: offset)
        }
        swipeMonitor.start()
    }

    /// 提示対象(文書 / フォルダー一覧)が入れ替わったときの追随を配線する。
    ///
    /// ツールバーの view ベースアイテムは validate を通らないため、提示対象が
    /// 変わったら明示的に再同期する(ADR 0002)。フォルダー一覧へ切り替わったときは
    /// キー入力の宛先も一覧へ移す(背後の見えない文書がキーを受け取り続けるのを防ぐ)。
    func wirePresentationTargetChange() {
        fileListModel.onPresentationTargetChange = { [weak self] in
            guard let self else { return }
            refreshToolbarState()
            if isPreviewingFolder { fileListModel.focusSidebarTable() }
        }
    }

    /// ViewerStore からの通知(ファイル消失・rename・再読込)をウィンドウ側の処理へ繋ぐ。
    ///
    /// init 本体ではなくここに置くのは、init を読むときに「何を購読するか」が 1 行に畳まれ、
    /// 購読内容の追加でウィンドウ生成手順の見通しが悪くならないようにするため。
    func wireStoreCallbacks() {
        store.onFileGone = { [weak self] in
            self?.window?.close()
        }
        store.onFileRenamed = { [weak self] oldURL, newURL in
            self?.handleRename(from: oldURL, to: newURL)
        }
        store.onContentReloaded = { [weak self] in
            self?.refreshToolbarState()
            // 表示中ファイルの保存に git バッジを追従させる。作業ツリーの編集は
            // `.git/index` を動かさないため index 監視では拾えず、ここが唯一の契機になる。
            // 再読込は FileWatcher のデバウンス後に 1 回来るので、連打にはならない。
            // 差分はここでは呼ばない。git 状態が反映された時点(gitStatusDidApply)で
            // 取り直すことで、バッジの全契機に差分が自動的に追従する(TASK-330)。
            self?.sidebar.refreshGitStatuses()
        }
    }
}
