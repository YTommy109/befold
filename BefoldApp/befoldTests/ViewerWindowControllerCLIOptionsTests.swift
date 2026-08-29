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

    @Test("CLI の --source/--preview 指定は記憶したソース表示モードより優先される")
    func sourceModeOverrideTakesPrecedenceOverRememberedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, sourceModeOverride: true
        ).controller
        defer { controller.close() }

        #expect(controller.isSourceMode)
        // 記憶自体は書き換えない(この起動限りの上書き)。
        #expect(controller.documentPresenter.presentationMemory.displayMode(for: file) == .rendered)
    }

    @Test("CLI のオプション未指定時は記憶したソース表示モードがそのまま復元される")
    func noSourceModeOverridePreservesRememberedValue() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let other = URL(fileURLWithPath: "/mock/other.md")
        let controller = ViewerWindowControllerFixture(
            file: file, extraFiles: [other], contents: "# hi", defaults: defaults
        ).controller
        defer { controller.close() }
        controller.setDisplayMode(.source)

        // 同じ窓の中で往復すると、記憶したモードが復元される。
        controller.switchFile(to: other)
        #expect(!controller.isSourceMode)
        controller.switchFile(to: file)

        #expect(controller.isSourceMode)
    }

    @Test("CLI の --source 上書き中にリネームされても、新 URL が対応形式ならソース表示が維持される")
    func sourceModeOverrideSurvivesRename() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, sourceModeOverride: true
        ).controller
        defer { controller.close() }
        #expect(controller.isSourceMode)

        // 記憶(.rendered)ではなく、いま表示中のモード(.source)が引き継がれる。
        controller.handleRename(from: file, to: URL(fileURLWithPath: "/mock/note.markdown"))

        #expect(controller.isSourceMode)
    }

    @Test("CLI の --source 上書き中でも、リネーム先が非対応形式ならソース表示は解除される")
    func sourceModeOverrideIsDemotedOnUnsupportedRename() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, sourceModeOverride: true
        ).controller
        defer { controller.close() }
        #expect(controller.isSourceMode)

        // .swift は supportsSourceMode == false のため降格する。
        controller.handleRename(from: file, to: URL(fileURLWithPath: "/mock/note.swift"))

        #expect(controller.isSourceMode == false)
    }

    @Test("CLI の --line-numbers 指定の有無で showLineNumbers・保存値への反映が決まる", arguments: [
        // (保存済みの値, CLI override, 期待する showLineNumbers, 期待する保存値)
        (saved: Bool?.none, override: Bool?.some (true), expectStore: true, expectSaved: Bool?.none),
        // fixture は既定で InMemoryFileReader + MockFileWatcher の store を自前生成して
        // 注入するため、このケースは「注入経路そのもの」の検証も兼ねている。
        (false, true, true, false), // override は保存済みグローバル設定を書き換えない
        (true, nil, true, nil), // 未指定時は保存済みの設定がそのまま復元される(true 方向)
        (false, nil, false, nil), // 未指定時は保存済みの設定がそのまま復元される(false 方向)
    ])
    func lineNumbersOverride(
        saved: Bool?, override: Bool?, expectStore: Bool, expectSaved: Bool?
    ) {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerCLIOptionsTests")
        if let saved {
            defaults.set(saved, forKey: "ShowLineNumbers")
        }

        let controller = ViewerWindowControllerFixture(
            file: file, contents: "# hi", defaults: defaults, showLineNumbersOverride: override
        ).controller
        defer { controller.close() }

        #expect(controller.store.showLineNumbers == expectStore)
        if let expectSaved {
            #expect(defaults.bool(forKey: "ShowLineNumbers") == expectSaved)
        }
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
