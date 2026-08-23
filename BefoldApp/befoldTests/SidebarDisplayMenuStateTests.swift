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
            ),
            canFilterChangedFiles: true
        )

        #expect(state.isEnabled)
        #expect(state.hidesHiddenFiles)
        #expect(state.checksChangedFilesOnly)
        #expect(state.checksTreeLayout)
    }

    @Test("ドリルダウン表示ではツリー項目にチェックが付かない")
    func drillDownDoesNotCheckTreeLayout() {
        #expect(menuState(settings(layoutMode: .tree)).checksTreeLayout)
        #expect(!menuState(settings()).checksTreeLayout)
    }

    /// 4 値は窓ごとのライブ値なので、届け先の窓が無い状態で項目を押せてはならない。
    @Test("アクティブウィンドウが無ければ項目は無効で、チェックも付かない")
    func disabledWithoutAnActiveWindow() {
        let state = SidebarDisplayMenuState(activeWindow: nil, canFilterChangedFiles: false)

        #expect(!state.isEnabled)
        #expect(!state.hidesHiddenFiles)
        #expect(!state.checksChangedFilesOnly)
        #expect(!state.checksTreeLayout)
        #expect(!state.canFilterChangedFiles)
    }

    /// git 管理外では「変更ファイルのみ表示」だけが無効になる。窓が無いときの無効化
    /// (`isEnabled`)とは条件が別で、他の 2 項目は使えたままであること(TASK-537)。
    @Test("git 管理外では変更ファイルのみ表示だけが選べない")
    func changedFilesOnlyNeedsGit() {
        let outsideGit = menuState(settings(), canFilterChangedFiles: false)
        #expect(outsideGit.isEnabled)
        #expect(!outsideGit.canFilterChangedFiles)

        let insideGit = menuState(settings(), canFilterChangedFiles: true)
        #expect(insideGit.isEnabled)
        #expect(insideGit.canFilterChangedFiles)
    }

    /// メニュー項目の有効判定そのもの。`validateMenuItem` は GUI なしに動かせないため、
    /// 判定を値型へ移してここで固定する(TASK-537)。git 管理外で無効になるのは
    /// 「変更ファイルのみ表示」**だけ**で、他の 2 項目は使えたまま。
    @Test("git 管理外で無効になるのは変更ファイルのみ表示だけ")
    func onlyChangedFilesOnlyNeedsGit() {
        let outsideGit = menuState(settings(), canFilterChangedFiles: false)

        #expect(!outsideGit.isEnabled(for: .toggleChangedFilesOnly))
        #expect(outsideGit.isEnabled(for: .toggleHiddenFiles))
        #expect(outsideGit.isEnabled(for: .toggleLayoutMode))
    }

    @Test("git 管理下では 3 項目とも使える")
    func allEnabledInsideGit() {
        let insideGit = menuState(settings(), canFilterChangedFiles: true)

        #expect(insideGit.isEnabled(for: .toggleChangedFilesOnly))
        #expect(insideGit.isEnabled(for: .toggleHiddenFiles))
        #expect(insideGit.isEnabled(for: .toggleLayoutMode))
    }

    /// 窓が無ければ git の可否によらず全項目が無効。2 つの条件が独立に効くことを固定する。
    @Test("アクティブウィンドウが無ければ git 管理下でも全項目が無効")
    func windowlessOverridesGitAvailability() {
        let noWindow = menuState(nil, canFilterChangedFiles: true)

        #expect(!noWindow.isEnabled(for: .toggleChangedFilesOnly))
        #expect(!noWindow.isEnabled(for: .toggleHiddenFiles))
        #expect(!noWindow.isEnabled(for: .toggleLayoutMode))
    }

    private func menuState(
        _ settings: SidebarDisplaySettings?, canFilterChangedFiles: Bool = true
    ) -> SidebarDisplayMenuState {
        SidebarDisplayMenuState(
            activeWindow: settings, canFilterChangedFiles: canFilterChangedFiles
        )
    }
}
