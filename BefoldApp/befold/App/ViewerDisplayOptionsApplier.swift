import AppKit
import BefoldCLI

/// CLI 由来の表示オプションを、既に開いているウィンドウ 1 つへ適用する規則。
///
/// 表示オプションが効く経路は 2 つある——新規ウィンドウは
/// `ViewerWindowController.init` の override 引数、既存ウィンドウはここ。
/// 後者に名前を与えて、適用規則そのものをウィンドウ生成なしに検証できるようにしている
/// (素通りさせるとフラグが黙って捨てられる: TASK-413)。
///
/// 知っているのは `CLIOpenOptions` の各フィールドと 1 つのコントローラへの適用順序だけ。
/// そのウィンドウが既存か新規か、他にいくつ窓が開いているか、前面化するかは知らない
/// (前面化は呼び出し側の責務)。同一ファイルが複数ウィンドウで開いていても適用先を
/// 1 つに揃えるのは、表示モードが窓ごとのライブ値だから(ADR 0002)。
@MainActor
enum ViewerDisplayOptionsApplier {
    /// options を controller へ適用する。
    /// - Parameter forceSidebarVisible: フォルダーオープンによるサイドバー強制表示。
    ///   CLI の明示指定(`--sidebar`/`--no-sidebar`)があればそちらが優先される。
    static func apply(
        _ options: CLIOpenOptions, to controller: ViewerWindowController, forceSidebarVisible: Bool
    ) {
        if let showLineNumbers = options.showLineNumbers {
            controller.store.lineNumbersSetting.applyOverride(showLineNumbers)
        }
        if let sourceMode = options.sourceMode { controller.applyCLIDisplayMode(isSourceMode: sourceMode) }
        // 並び順は「指定があったときだけ」触る。viewerSortOrder は未指定でも既定値を
        // 返すため、指定の有無は sortOrder の nil 判定で見る。
        // ここはこの起動限りの窓単位の上書きなので、保存された既定値
        // (SidebarDisplayDefaults.sortOrder)は意図的に書き換えない。利用者の操作は
        // SidebarNavigator.setSortOrder(_:) を通り、そちらは既定値も更新する。
        if options.sortOrder != nil {
            controller.fileListModel.sortOrder = options.viewerSortOrder
            controller.sidebar.refreshFileList()
        }
        // 開閉の解決順は新規ウィンドウ(openViewer)と同じ: CLI の明示指定 > フォルダーオープンの強制表示。
        if let showSidebar = options.showSidebar {
            controller.setSidebarCollapsed(!showSidebar)
        } else if forceSidebarVisible {
            controller.setSidebarCollapsed(false)
        }
        // store の直接書き換え(行番号の上書き)はツールバーへ通知されないため、
        // 他経路の間接発火に頼らずここで明示的に再同期する。
        controller.refreshToolbarState()
    }
}
