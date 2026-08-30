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
    static func makeSidebarGitReader(
        fileIndex: any GitFileIndexing,
        statusStore: GitStatusStore
    ) -> any SidebarGitReading {
        SidebarGitReader(fileIndex: fileIndex, statusStore: statusStore)
    }

    /// サイドバー（一覧・選択同期・フォルダ移動）のナビゲータを作る。
    /// コントローラの `super.init` より前に呼ぶため、self を要らない形にしてある。
    /// 窓の最初の文書を開くまでの一連の配線。順序に意味があるのでここへ寄せる。
    ///
    /// 1. 起点の窓が同じフォルダを列挙済みなら、その結果を出発点にする(TASK-532)
    /// 2. サイドバー一覧を埋める(列挙はメインアクター外で走る)。引き継ぎが効いて
    ///    いれば同じ結果が返り、applyRows のガードが反映ごと畳む
    /// 3. ストアのコールバックを配線してから開く(開いた直後の通知を取り落とさない)
    static func openInitialDocument(
        for controller: ViewerWindowController, at fileURL: URL,
        adopting initialListing: SidebarListingSeed?
    ) {
        controller.sidebar.attach(to: controller, adopting: initialListing)
        controller.sidebar.refreshFileList()
        wireStoreCallbacks(for: controller)
        controller.store.openFile(fileURL)
    }

    static func makeSidebarNavigator(
        fileURL: URL,
        displayDefaults: SidebarDisplayDefaults,
        overrides: SidebarDisplayOverrides,
        gitFileIndex: any GitFileIndexing,
        gitStatusStore: GitStatusStore
    ) -> SidebarNavigator {
        // 初期一覧は空で始め、attach 直後の refreshFileList()（非同期の DirectoryLister.listingAsync）に
        // 埋めさせる。ウィンドウ生成時だけ同期列挙する経路を持たないことで、ネットワーク
        // ボリューム上のフォルダでもウィンドウ表示がディレクトリ列挙を待たない。
        SidebarNavigator(
            currentDirectory: fileURL.deletingLastPathComponent(), entries: [], selection: fileURL,
            displayDefaults: displayDefaults, sortOrder: overrides.sortOrder,
            showHiddenFiles: overrides.showHiddenFiles,
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
    static func makeWebViewCommands(
        for controller: ViewerWindowController
    ) -> DocumentCommandController {
        DocumentCommandController(
            // WKWebView と JS の詳細は adapter に閉じ（ADR 0002 段 4）、どの面へ届けるかの
            // 決定は束（DocumentSurfaces）に閉じる（TASK-564.6）。
            surfaces: controller.surfaces,
            perFileState: controller.perFileState,
            // 現在 URL は rename/switch で書き換わる。窓と同じ共有参照を渡し、旧値を捕捉しない。
            currentDocument: controller.currentDocument,
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
            // 開く対象の種別。PDF なら WKWebView を作らずに始める(TASK-564.7)。
            openingFileType: FileType(url: controller.fileURL),
            findOptionsPreference: controller.findOptionsPreference,
            headingJump: controller.headingJump,
            codeFontFamily: controller.codeFontPreference.fontFamily,
            codeFontSizePoints: controller.codeFontPreference.fontSizePoints,
            csvGrouping: controller.csvNumberFormatPreference.grouping,
            csvNegativeStyle: controller.csvNumberFormatPreference.negativeStyle,
            fileListModel: controller.fileListModel,
            rendererDelegate: WeakRendererDelegate(controller),
            onSelectFile: onSelectFile,
            onNavigateToFolder: onNavigateToFolder,
            webViewProxy: controller.surfaces.web,
            pdfViewProxy: controller.surfaces.pdf,
            pdfActions: PDFSurfaceActions(
                // 面の中で完結する倍率操作の受け口。届いた倍率の扱い(ライブ値と保存値)は
                // JS 由来の倍率通知と同じ 1 箇所へ寄せる。
                onZoomChanged: { [weak controller] zoom in
                    guard let controller else { return }
                    controller.documentPresenter.recordZoomChange(zoom, for: controller.currentDocument.url)
                },
                // 回転はコマンド経路を通す(可否の判断は capabilities が持つ)。
                onRotate: { [weak controller] degrees in
                    controller?.documentCommands.rotate(byDegrees: degrees)
                }
            ),
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
            },
            onSidebarDidHide: { [weak controller] in
                controller?.fileListModel.tableFocuser.cancelPendingFocus()
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
                controller?.sidebar.applyDisplayChange(.setSortOrder(order))
            },
            onToggleHiddenFiles: makeDisplayToggle(.toggleHiddenFiles, for: controller),
            onToggleChangedFilesOnly: makeDisplayToggle(.toggleChangedFilesOnly, for: controller),
            onToggleSidebarTreeLayout: makeDisplayToggle(.toggleLayoutMode, for: controller)
        )
    }

    /// サイドバーヘッダーのトグルボタンの動作を作る。
    ///
    /// サイドバー表示 4 値は窓ごとのライブ値なので(ADR 0002「窓の状態」)、**この窓の
    /// サイドバーへ直接届ける。** メニュー(⌃⌘T など)も同じ
    /// `SidebarNavigator.applyDisplayChange(_:)` を通り、ボタン専用の経路は持たせない。
    /// 以前は delegate → `ViewerWindowManager` → 全窓一括反映という経路だったが、
    /// 配る先が 1 窓になった今、窓の外を往復する理由が無い(TASK-480.3)。
    static func makeDisplayToggle(
        _ change: SidebarDisplayChange, for controller: ViewerWindowController
    ) -> () -> Void {
        { [weak controller] in
            controller?.sidebar.applyDisplayChange(change)
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
            controller.refreshUIState()
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
            controller?.refreshUIState()
            // 表示中ファイルの保存に git バッジを追従させる。作業ツリーの編集は
            // `.git/index` を動かさないため index 監視では拾えず、ここが唯一の契機になる。
            // 再読込は FileWatcher のデバウンス後に 1 回来るので、連打にはならない。
            // 差分はここでは呼ばない。git 状態が反映された時点（gitContextDidChange）で
            // 取り直すことで、バッジの全契機に差分が自動的に追従する（TASK-330）。
            controller?.sidebar.refreshGitStatuses()
        }
    }
}
