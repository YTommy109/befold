import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 差分表示のトグルが「いま何ができるか」(ViewerCapabilities)だけを見ていることを確かめる。
/// フォルダー一覧を出している間に効いてしまうと、見えていない文書に対する操作になる
/// (TASK-271 と同じ形の穴)。
@Suite
@MainActor
struct ViewerWindowControllerDiffTests {
    private let file = URL(fileURLWithPath: "/mock/note.swift")

    private func makeController(preference: DiffDisplayPreference) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests"),
            diffDisplayPreference: preference
        ).controller
    }

    private func makePreference() -> DiffDisplayPreference {
        DiffDisplayPreference(
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests.pref"),
            isAvailable: true
        )
    }

    @Test("文書を提示している間はトグルできる")
    func togglesWhilePresentingDocument() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.isSourceMode = true
        // 前提そのものを固定する(能力が false のままだと、以下のトグルは
        // 「効かなかった」のか「そもそも対象外だった」のか区別できない)。
        #expect(controller.capabilities.canToggleDiff)

        controller.toggleSourceDiff(nil)

        #expect(preference.isEnabled)
    }

    @Test("フォルダー提示中はトグルが効かない")
    func ignoresToggleWhilePreviewingFolder() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        let folder = URL(fileURLWithPath: "/mock/sub")
        controller.fileListModel.entries = [
            FileListEntry(url: file, kind: .file),
            FileListEntry(url: folder, kind: .folder),
        ]
        controller.fileListModel.selection = folder
        controller.store.isSourceMode = true
        #expect(!controller.capabilities.canToggleDiff)

        controller.toggleSourceDiff(nil)
        controller.toggleDiffLayout(nil)

        #expect(controller.isPreviewingFolder)
        #expect(preference.isEnabled == false)
        #expect(preference.layout == .inline)
    }

    @Test("レイアウトはインラインと左右分割を往復する")
    func togglesLayoutBothWays() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.isSourceMode = true

        controller.toggleDiffLayout(nil)
        #expect(preference.layout == .sideBySide)

        controller.toggleDiffLayout(nil)
        #expect(preference.layout == .inline)
    }

    /// 設定が OFF なら、以前の取得結果が残っていても差分は出さない。
    @Test("差分表示を OFF にすると本文が捨てられる")
    func clearsDiffTextWhenDisabled() {
        let preference = makePreference()
        preference.isEnabled = true
        let controller = makeController(preference: preference)
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.isSourceMode = true
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        controller.toggleSourceDiff(nil)

        #expect(preference.isEnabled == false)
        #expect(controller.store.diffText == nil)
    }
}
