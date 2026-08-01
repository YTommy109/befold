import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// CLI から渡される表示オプション(隠しファイル・並び順・行番号・ソース/プレビューモード)が
/// ウィンドウオープン時に適用されることを検証する。
///
/// これらは init 時のオプション適用のみが検証対象で、実ファイル内容には依存しないため、
/// ViewerWindowControllerFixture(実 WKWebView 無し、InMemoryFileReader + MockFileWatcher)を使う
/// unit テストとして構成する。
@Suite
@MainActor
struct ViewerWindowControllerCLIOptionsTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/note.md")

    @Test("CLI の --source/--preview 指定は保存済みのソース表示モードより優先される")
    func sourceModeOverrideTakesPrecedenceOverSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(false, for: file)

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults,
            sourceModeStore: sourceModeStore, sourceModeOverride: true
        ).controller
        defer { controller.close() }

        #expect(controller.isSourceMode)
        // 保存値自体は書き換えない(この起動限りの上書き)。
        #expect(!sourceModeStore.isSourceMode(for: file))
    }

    @Test("CLI のオプション未指定時は保存済みのソース表示モードがそのまま復元される")
    func noSourceModeOverridePreservesSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let sourceModeStore = SourceModeStore(defaults: defaults)
        sourceModeStore.setSourceMode(true, for: file)

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, sourceModeStore: sourceModeStore
        ).controller
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }

    @Test("CLI の --line-numbers 指定は showLineNumbers に反映される")
    func lineNumbersOverrideIsAppliedToStore() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, showLineNumbersOverride: true
        ).controller
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
    }

    @Test("CLI の --line-numbers 指定は保存済みのグローバル設定を書き換えない")
    func lineNumbersOverrideDoesNotPersistToUserDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(false, forKey: "ShowLineNumbers")

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, showLineNumbersOverride: true
        ).controller
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
        #expect(!defaults.bool(forKey: "ShowLineNumbers"))
    }

    @Test("CLI のオプション未指定時は保存済みの行番号設定がそのまま復元される")
    func noLineNumbersOverridePreservesSavedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(true, forKey: "ShowLineNumbers")

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults
        ).controller
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
    }

    @Test("store を明示注入した場合でも --line-numbers 指定が反映される")
    func lineNumbersOverrideIsAppliedEvenWithExplicitStore() {
        // fixture は既定で InMemoryFileReader + MockFileWatcher の store を自前生成して
        // 注入するため、これは実質「注入経路そのもの」を検証している。
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        defaults.set(false, forKey: "ShowLineNumbers")

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, showLineNumbersOverride: true
        ).controller
        defer { controller.close() }

        #expect(controller.store.showLineNumbers)
        #expect(!defaults.bool(forKey: "ShowLineNumbers"))
    }

    @Test("CLI の --sort 指定はサイドバーの並び順(FileListModel.sortOrder)に反映される")
    func sortOrderOverrideIsAppliedToFileListModel() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, initialSortOrder: .alphabetical
        ).controller
        defer { controller.close() }

        // 一覧の取得自体は非同期(SidebarNavigator)へ寄せたため、ここでは並び順が
        // サイドバーのモデルへ届いていることを見る。実際の並べ替えは DirectoryLister 側のテストが担う。
        #expect(controller.fileListModel.sortOrder == .alphabetical)
    }
}
