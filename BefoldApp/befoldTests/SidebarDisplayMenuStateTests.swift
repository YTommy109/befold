@testable import befold
import Testing

/// View メニューのサイドバー表示 3 項目が、**アクティブウィンドウの現在値**を映すこと
/// (TASK-480.3)。保存された既定値を映す形へ戻すと、前面の窓と食い違ったチェック状態になる。
@Suite
@MainActor
struct SidebarDisplayMenuStateTests {
    private func settings(
        showHiddenFiles: Bool = false, showChangedFilesOnly: Bool = false,
        layoutMode: SidebarLayoutMode = .drillDown
    ) -> SidebarDisplaySettings {
        SidebarDisplaySettings(
            showHiddenFiles: showHiddenFiles, showChangedFilesOnly: showChangedFilesOnly,
            layoutMode: layoutMode, sortOrder: .foldersFirst
        )
    }

    @Test("アクティブウィンドウの値がそのままチェック状態になる")
    func reflectsActiveWindowValues() {
        let state = SidebarDisplayMenuState(
            activeWindow: settings(
                showHiddenFiles: true, showChangedFilesOnly: true, layoutMode: .tree
            )
        )

        #expect(state.isEnabled)
        #expect(state.hidesHiddenFiles)
        #expect(state.checksChangedFilesOnly)
        #expect(state.checksTreeLayout)
    }

    @Test("ドリルダウン表示ではツリー項目にチェックが付かない")
    func drillDownDoesNotCheckTreeLayout() {
        #expect(SidebarDisplayMenuState(activeWindow: settings(layoutMode: .tree)).checksTreeLayout)
        #expect(!SidebarDisplayMenuState(activeWindow: settings()).checksTreeLayout)
    }

    /// 4 値は窓ごとのライブ値なので、届け先の窓が無い状態で項目を押せてはならない。
    @Test("アクティブウィンドウが無ければ項目は無効で、チェックも付かない")
    func disabledWithoutAnActiveWindow() {
        let state = SidebarDisplayMenuState(activeWindow: nil)

        #expect(!state.isEnabled)
        #expect(!state.hidesHiddenFiles)
        #expect(!state.checksChangedFilesOnly)
        #expect(!state.checksTreeLayout)
    }
}
