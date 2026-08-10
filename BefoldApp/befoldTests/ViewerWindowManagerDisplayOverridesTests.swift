import AppKit
@testable import befold
import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// CLI 由来の表示オプション(`--line-numbers` / `--source` / `--sort` / `--sidebar`)が
/// openViewer の単一経路で適用されることを検証する。
///
/// 新規ウィンドウは init の override 引数、既に開いているウィンドウは重複抑止枝での適用と
/// 経路が分かれるが、**同じ結果になる**ことをここで固定する。かつて既存ウィンドウ向けには
/// applyDisplayOverrides という別経路があり、そちらだけが保存値を書き換えていた(TASK-413)。
/// コントローラ生成は MockedViewerWindowManager 経由でモック化しているため実 FS を踏まない。
/// サイドバー entries の並び替え結果そのものを見る検証は
/// ViewerWindowManagerDisplayOverridesIntegrationTests に残している。
@Suite
@MainActor
struct ViewerWindowManagerDisplayOverridesTests {
    private let file = URL(fileURLWithPath: "/mock/first.mmd")
    private let imageFile = URL(fileURLWithPath: "/mock/shot.png")

    /// 全フィールドを指定した表示オプション。CLIOpenOptions にフィールドが増えたら
    /// befoldCLITests の optionFieldsAreEnumeratedExhaustively が落ちるので、
    /// ここへ足し忘れたまま気付かない形にはならない。
    private var allOptions: CLIOpenOptions {
        CLIOpenOptions(sortOrder: .alphabetical, showLineNumbers: true, sourceMode: true, showSidebar: true)
    }

    @Test("既に開いているファイルを指定すると、そのウィンドウへ表示オプションが適用される")
    func openViewerAppliesOptionsToAlreadyOpenWindow() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "OptionsOnOpenWindow")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        #expect(!controller.store.showLineNumbers)
        #expect(!controller.isSourceMode)
        #expect(controller.fileListModel.sortOrder == .foldersFirst)
        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)

        fixture.manager.openViewer(for: file, options: allOptions)

        // 新しいウィンドウは作らず、開いているウィンドウへ届く。
        #expect(fixture.manager.controllers[file.normalizedPathKey]?.count == 1)
        #expect(controller.store.showLineNumbers)
        #expect(controller.isSourceMode)
        #expect(controller.fileListModel.sortOrder == .alphabetical)
        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }

    @Test("既存ウィンドウへの表示オプション適用でもツールバーが再同期される")
    func openViewerOnOpenWindowRefreshesToolbar() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "OptionsToolbarRefresh")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let toolbar = try #require(controller.window?.toolbar)
        let liveItem = try #require(toolbar.items.first { $0.itemIdentifier == .init("lineNumbers") })
        let button = try #require(liveItem.view as? NSButton)
        #expect(button.contentTintColor == nil)

        // 行番号だけを上書きする(他オプションの間接発火に頼れない経路)。
        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showLineNumbers: true))

        #expect(button.contentTintColor == .controlAccentColor)
    }

    @Test("未指定(nil)のオプションは既に開いているウィンドウの状態を変えない")
    func openViewerLeavesUnspecifiedOptionsUntouched() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "OptionsUnspecified")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        let originalSortOrder = controller.fileListModel.sortOrder
        let originalSourceMode = controller.isSourceMode

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showLineNumbers: true))

        #expect(controller.store.showLineNumbers)
        #expect(controller.isSourceMode == originalSourceMode)
        #expect(controller.fileListModel.sortOrder == originalSortOrder)
    }

    /// ADR 0002 の永続化規則「保存値へ書くのは明示的なユーザーのモード選択だけ」。
    /// CLI の上書きはこの起動限りで、新規ウィンドウ・既存ウィンドウのどちらでも保存値を触らない。
    @Test("CLI の表示モード上書きは既存ウィンドウでも保存値を書き換えない")
    func openViewerOnOpenWindowDoesNotPersistDisplayMode() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "OptionsNoPersist")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        #expect(fixture.perFileState.displayMode.displayMode(for: file) == .rendered)

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(sourceMode: true))

        #expect(fixture.perFileState.displayMode.displayMode(for: file) == .rendered)
    }

    /// フォルダーを開いた結果が既に開いているファイルへ解決される場合も、サイドバーの
    /// 強制表示は効く。options だけを適用して forceSidebarVisible を落とすと同型の穴が残る。
    @Test("既に開いているファイルでも forceSidebarVisible はサイドバーを開く")
    func openViewerOnOpenWindowHonorsForceSidebarVisible() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "OptionsForceSidebar")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: false))
        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)

        fixture.manager.openViewer(for: file, forceSidebarVisible: true)

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }

    /// 降格規則は DisplayModeStore.supportedDisplayMode の 1 箇所（ADR 0002）。
    /// ソース表示を持たない種別へ --source を渡しても、その規則を通って .rendered に落ちる。
    @Test("ソース表示を持たない種別への --source は新規・既存のどちらの経路でも降格する")
    func sourceModeOverrideIsDemotedForUnsupportedType() throws {
        let fixture = MockedViewerWindowManager(files: [imageFile], prefix: "OptionsDemotion")
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: imageFile, options: CLIOpenOptions(sourceMode: true))
        let controller = try #require(fixture.manager.controllers[imageFile.normalizedPathKey]?.first)
        #expect(!controller.isSourceMode)

        fixture.manager.openViewer(for: imageFile, options: CLIOpenOptions(sourceMode: true))

        #expect(!controller.isSourceMode)
    }

    @Test(
        "新規ウィンドウは options.showSidebar に従って開閉状態が決まる",
        arguments: [(true, false), (false, true)]
    )
    func sidebarVisibleOverrideDeterminesInitialCollapse(visible: Bool, expectedCollapsed: Bool) {
        let fixture = MockedViewerWindowManager(
            files: [file], prefix: "SidebarOverrideInitial-\(visible)"
        )
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: visible))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == expectedCollapsed)
    }

    @Test("showSidebar 未指定(nil)なら保存済み開閉状態を維持する")
    func sidebarVisibleOverrideNilKeepsSavedState() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SidebarOverrideNil")
        defer { fixture.closeAll() }
        // 事前に「開いた状態(collapsed=false)」を保存しておく。
        fixture.perFileState.sidebar.setCollapsed(false, for: file)

        fixture.manager.openViewer(for: file, options: CLIOpenOptions(showSidebar: nil))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == false)
    }
}
