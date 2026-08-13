import AppKit
import BefoldKit
import SwiftUI

/// ビューアウィンドウの部品を作り、配線を張る組み立て役。
///
/// `ViewerWindowController` の init が踏む各工程の**中身**だけをここへ集める。
/// **工程どうしの順序制約は init 側に残す**（順序をここへ束ねると、init を読んでも
/// ウィンドウ生成手順が追えなくなる）。したがってここに置く関数はどれも
/// 「呼ばれた時点の状態だけを見て 1 つの部品を作る / 1 本の配線を張る」形にしてある。
///
/// コントローラを引数で受ける関数は、生成物のクロージャがコントローラを弱参照で
/// 捕捉するためのもの。組み立て役自身は状態を持たない（インスタンス化しない enum）。
@MainActor
enum ViewerWindowAssembler {
    // MARK: - super.init より前に呼べる部品

    /// サイドバーへ渡す git 状態の取得クロージャを作る。
    ///
    /// ロジック自体は常時ビルドし、露出点だけを囲う（無効時は機能を消すのではなく空を返す）。
    /// git ステータス系の露出点はここを含めて 3 箇所あり、一覧は FeatureGate の宣言にある。
    /// stable 昇格（TASK-187）ではこの guard を消して常に store を引く形にすればよい。
    static func makeSidebarGitReader(
        fileIndex: any GitFileIndexing, statusStore: GitStatusStore
    ) -> any SidebarGitReading {
        // ゲートで止めるのは状態取得だけ。リポジトリルートの解決(基準ディレクトリ表示)は
        // ゲート対象外なので、reader は常に作り statusStore の有無で状態取得だけを落とす。
        SidebarGitReader(
            fileIndex: fileIndex,
            statusStore: FeatureGate.isSidebarGitStatusEnabled ? statusStore : nil
        )
    }

    /// サイドバー（一覧・選択同期・フォルダ移動）のナビゲータを作る。
    /// コントローラの `super.init` より前に呼ぶため、self を要らない形にしてある。
    static func makeSidebarNavigator(
        fileURL: URL,
        sidebarDisplayPreference: SidebarDisplayPreference,
        sortOrder: SortOrder,
        gitFileIndex: any GitFileIndexing,
        gitStatusStore: GitStatusStore
    ) -> SidebarNavigator {
        // 初期一覧は空で始め、attach 直後の refreshFileList()（非同期の DirectoryLister.listingAsync）に
        // 埋めさせる。ウィンドウ生成時だけ同期列挙する経路を持たないことで、ネットワーク
        // ボリューム上のフォルダでもウィンドウ表示がディレクトリ列挙を待たない。
        SidebarNavigator(
            currentDirectory: fileURL.deletingLastPathComponent(), entries: [], selection: fileURL,
            sidebarDisplayPreference: sidebarDisplayPreference, sortOrder: sortOrder,
            git: makeSidebarGitReader(fileIndex: gitFileIndex, statusStore: gitStatusStore)
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

    // MARK: - コントローラを要る部品

    /// WebView 操作系メニューアクション（ズーム・印刷・検索・スクロール位置保存）の実処理を作る。
    /// - Parameter fallbackURL: コントローラが解放済みのときに使う URL（生成時のファイル）。
    static func makeWebViewCommands(
        for controller: ViewerWindowController,
        documentRenderer: (any DocumentRendering)?,
        fallbackURL: URL
    ) -> WebViewCommandController {
        WebViewCommandController(
            // WKWebView と JS の詳細は adapter に閉じる（ADR 0002 段 4）。
            renderer: documentRenderer ?? WebViewDocumentRenderer(webViewProxy: controller.webViewProxy),
            perFileState: controller.perFileState,
            // 現在 URL は rename/switch で書き換わるため、旧値を捕捉せずコントローラ経由で参照する。
            currentURL: { [weak controller] in controller?.fileURL ?? fallbackURL },
            onZoomChanged: { [weak controller] zoom in controller?.store.zoom = zoom },
            onScrollPositionSaved: { [weak controller] position, url, mode in
                controller?.applySavedScrollPositionToLiveValue(position, for: url, mode: mode)
            },
            // 実行可否は capabilities に集約する（ADR 0002）。フォルダー一覧を表示している間も
            // WKWebView は背後に生き続けるため、見えていない文書への操作はここで止まる。
            capabilities: { [weak controller] in controller?.capabilities ?? .none }
        )
    }

    /// サイドバー（ファイル一覧）とコンテンツ（WebView/フォルダー一覧）を並べる split view controller を組み立てる。
    ///
    /// 生成した split view controller は `controller.sidebarCollapsible` にも設定する
    /// （CLI の `--sidebar` / `--no-sidebar` 適用が後から参照するため）。
    static func makeSplitViewController(
        for controller: ViewerWindowController, contentOverride: (() -> AnyView)?
    ) -> NSViewController {
        let onSelectFile: (URL) -> Void = { [weak controller] url in controller?.switchFile(to: url) }
        let onNavigateToFolder: (URL) -> Void = { [weak controller] url in controller?.navigateToFolder(url) }
        let content: AnyView = contentOverride?() ?? AnyView(ViewerContentView(
            store: controller.store,
            findOptionsPreference: controller.findOptionsPreference,
            codeFontFamily: controller.codeFontPreference.fontFamily,
            codeFontSizePoints: controller.codeFontPreference.fontSizePoints,
            fileListModel: controller.fileListModel,
            rendererDelegate: WeakRendererDelegate(controller),
            onSelectFile: onSelectFile,
            onNavigateToFolder: onNavigateToFolder,
            webViewProxy: controller.webViewProxy,
            diffDisplayPreference: controller.diffDisplayPreference
        ))
        let splitViewController = ViewerSplitViewController(
            sidebar: makeFileListView(for: controller),
            content: content,
            initialCollapsed: controller.initialSidebarCollapsed,
            onCollapsedChange: { [weak controller] collapsed in
                guard let controller else { return }
                controller.perFileState.sidebar.recordToggle(collapsed, for: controller.fileURL)
            },
            onSidebarDidReveal: { [weak controller] in
                controller?.fileListModel.tableFocuser.focus()
            }
        )
        controller.sidebarCollapsible = splitViewController
        return splitViewController
    }

    /// サイドバーのファイル一覧ビューを組み立てる。
    ///
    /// 行操作(選択・移動・別の場所で開く・展開/畳み)は controller が
    /// `FileListViewDelegate` として直接受けるため、ここでは配線しない。
    private static func makeFileListView(for controller: ViewerWindowController) -> FileListView {
        FileListView(
            model: controller.fileListModel,
            delegate: controller,
            onSortOrderChanged: { [weak controller] order in
                guard let controller else { return }
                controller.fileListModel.sortOrder = order
                controller.sidebar.refreshFileList()
            },
            onToggleHiddenFiles: { [weak controller] in
                guard let controller else { return }
                controller.delegate?.viewerWindowDidToggleHiddenFiles(controller)
            },
            onToggleChangedFilesOnly: makeChangedFilesOnlyToggle(for: controller)
        )
    }

    /// サイドバーヘッダーの「変更されたファイルのみ表示」ボタンの動作を作る。
    ///
    /// git ステータスと同じ開発中機能の露出点であり、無効なら nil を返して
    /// ボタン自体を出さない（FileListView 側が nil で非表示にする）。
    private static func makeChangedFilesOnlyToggle(
        for controller: ViewerWindowController
    ) -> (() -> Void)? {
        guard FeatureGate.isSidebarGitStatusEnabled else { return nil }
        return { [weak controller] in
            guard let controller else { return }
            controller.delegate?.viewerWindowDidToggleChangedFilesOnly(controller)
        }
    }

    // MARK: - 配線

    /// 二本指スワイプによるファイル履歴ナビゲーション検知を作る。
    /// 開始まで済ませて返す。停止は windowWillClose が行う
    /// （`ViewerWindowController+WindowDelegate.swift`）。
    static func makeSwipeMonitor(
        for controller: ViewerWindowController, on window: NSWindow
    ) -> SwipeHistoryMonitor {
        let monitor = SwipeHistoryMonitor(window: window) { [weak controller] offset in
            controller?.navigateHistory(by: offset)
        }
        monitor.start()
        return monitor
    }

    /// 提示対象（文書 / フォルダー一覧）が入れ替わったときの追随を配線する。
    ///
    /// ツールバーの view ベースアイテムは validate を通らないため、提示対象が
    /// 変わったら明示的に再同期する（ADR 0002）。フォルダー一覧へ切り替わったときは
    /// キー入力の宛先も一覧へ移す（背後の見えない文書がキーを受け取り続けるのを防ぐ）。
    ///
    /// タイトルとプロキシアイコンもここで追随させる。ファイル URL が動く契機
    /// （生成・切替・リネーム）だけを見ていると、フォルダー一覧へ切り替わったときは
    /// URL が動かないため直前のファイル名が残る（TASK-469）。導出規則そのものは
    /// `ViewerWindowChrome.applyURL` の 1 箇所にあり、ここは契機を足すだけ。
    static func wirePresentationTargetChange(for controller: ViewerWindowController) {
        controller.fileListModel.onPresentationTargetChange = { [weak controller] in
            guard let controller else { return }
            controller.refreshToolbarState()
            controller.applyURLToWindow(controller.fileURL)
            if controller.isPreviewingFolder { controller.fileListModel.tableFocuser.focus() }
        }
    }

    /// ViewerStore からの通知（ファイル消失・rename・再読込）をウィンドウ側の処理へ繋ぐ。
    static func wireStoreCallbacks(for controller: ViewerWindowController) {
        controller.store.onFileGone = { [weak controller] in
            controller?.window?.close()
        }
        controller.store.onFileRenamed = { [weak controller] oldURL, newURL in
            controller?.handleRename(from: oldURL, to: newURL)
        }
        controller.store.onContentReloaded = { [weak controller] in
            controller?.refreshToolbarState()
            // 表示中ファイルの保存に git バッジを追従させる。作業ツリーの編集は
            // `.git/index` を動かさないため index 監視では拾えず、ここが唯一の契機になる。
            // 再読込は FileWatcher のデバウンス後に 1 回来るので、連打にはならない。
            // 差分はここでは呼ばない。git 状態が反映された時点（gitStatusDidApply）で
            // 取り直すことで、バッジの全契機に差分が自動的に追従する（TASK-330）。
            controller?.sidebar.refreshGitStatuses()
        }
    }
}
