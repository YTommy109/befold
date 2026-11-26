import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 戻る・進むは、記録した意図を本文へ書いてからサイドバーを合わせる(ADR 0013 決定 2 /
/// TASK-930.5)。記録は意図を書いた時点で行い、一覧の着地を待たない。
@Suite
@MainActor
struct ViewerWindowHistoryPresentationTests {
    private struct Fixture {
        let tmp: TempDir
        let controller: ViewerWindowController
        let base: URL
        let sub: URL
        let deep: URL
        let other: URL
        let inOther: URL
    }

    /// base/{a.md, sub/deep.md} と other/t.md を作り、base/a.md を開いた窓を返す。
    private func makeFixture(layout: SidebarLayoutMode, prefix: String) async throws -> Fixture {
        let tmp = try TempDir()
        let base = tmp.url.appendingPathComponent("base", isDirectory: true)
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let other = tmp.url.appendingPathComponent("other", isDirectory: true)
        for dir in [sub, other] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let first = base.appendingPathComponent("a.md")
        let deep = sub.appendingPathComponent("deep.md")
        let inOther = other.appendingPathComponent("t.md")
        for file in [first, deep, inOther] {
            try Data("# x".utf8).write(to: file)
        }
        let defaults = makeIsolatedDefaults(prefix: prefix)
        let preference = SidebarDisplayDefaults(defaults: defaults)
        preference.record { $0.layoutMode = layout }
        let controller = ViewerWindowControllerFixture(
            file: first, realFileSystem: true, defaults: defaults, displayDefaults: preference
        ).controller
        await controller.sidebar.awaitSettled()
        return Fixture(
            tmp: tmp, controller: controller, base: base, sub: sub, deep: deep, other: other, inOther: inOther
        )
    }

    /// 意図が通った値と、その瞬間のサイドバーの表示中フォルダーを記録する。
    /// 窓の再同期(`onChange` の既存の配線)はそのまま呼ぶ。
    @MainActor
    private final class TargetRecorder {
        private(set) var targets: [PreviewTarget] = []
        /// 意図が書かれた瞬間の `currentDirectory`。意図 → サイドバーの順を見る。
        private(set) var directoriesAtWrite: [URL] = []

        init(_ controller: ViewerWindowController) {
            let intent = controller.presentationIntent
            let original = intent.onChange
            intent.onChange = { [weak self, weak intent, weak controller] in
                if let intent { self?.targets.append(intent.target) }
                if let controller { self?.directoriesAtWrite.append(controller.fileListModel.currentDirectory) }
                original?()
            }
        }

        var passedThroughFolder: Bool {
            targets.contains { $0.folderURL != nil }
        }
    }

    @Test("別フォルダーへの移動を伴うフォルダー一覧の履歴へ戻ると、サイドバーより先にその一覧を出す", arguments: [SidebarLayoutMode.tree, .drillDown])
    func goingBackToFolderEntryPresentsListingBeforeSidebar(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "HistoryPresentation.folder.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        // other の一覧(文書は a.md のまま)→ sub/deep.md を開く(サイドバーは sub へ移る)。
        controller.navigateToFolder(fixture.other)
        await controller.sidebar.awaitSettled()
        controller.switchFile(to: fixture.deep)
        await controller.sidebar.awaitSettled()
        let before = controller.fileListModel.currentDirectory
        #expect(before.normalizedPathKey != fixture.other.normalizedPathKey)
        let recorder = TargetRecorder(controller)

        controller.navigateHistory(by: -1)

        // 一覧の着地を待たずに other の一覧が出ている。
        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.other))
        // 文書(a.md)へ戻す切替が書く .file は、文書を出していたので変化にならない。
        #expect(recorder.targets == [.folder(fixture.other)], "意図の遷移: \(recorder.targets)")
        // フォルダーの意図を書いた時点では、サイドバーはまだ動いていない。
        #expect(recorder.directoriesAtWrite.last?.normalizedPathKey == before.normalizedPathKey)
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.other))
        #expect(controller.fileListModel.currentDirectory.normalizedPathKey == fixture.other.normalizedPathKey)
    }

    /// 別の文書を伴うフォルダーのエントリへ、フォルダー一覧の表示中から(履歴メニューで 2 つ)戻る。
    /// 文書へ戻す切替が `.file` を書き、同じ同期区間の中でフォルダーへ書き直す。切替に提示を渡す
    /// 口は足さない(サイドバー側の型が意図を書ける形になるため / ADR 0013)ので、この 2 回を固定する。
    @Test("別の文書を伴うフォルダー一覧の履歴へ戻ると、文書の切替の直後にサイドバーより先にその一覧を出す", arguments: [SidebarLayoutMode.tree, .drillDown])
    func goingBackToFolderEntryWithOtherDocumentWritesFileThenFolder(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "HistoryPresentation.twoWrites.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        controller.navigateToFolder(fixture.other) // 戻り先: other の一覧(文書は a.md)
        await controller.sidebar.awaitSettled()
        controller.switchFile(to: fixture.inOther)
        await controller.sidebar.awaitSettled()
        controller.navigateToFolder(fixture.sub) // sub の一覧(文書は t.md)
        await controller.sidebar.awaitSettled()
        let recorder = TargetRecorder(controller)

        controller.navigateHistory(by: -2)

        #expect(recorder.targets == [.file, .folder(fixture.other)], "意図の遷移: \(recorder.targets)")
        #expect(recorder.directoriesAtWrite.last?.normalizedPathKey == fixture.sub.normalizedPathKey)
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.other))
        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(controller.fileListModel.currentDirectory.normalizedPathKey == fixture.other.normalizedPathKey)
    }

    enum FileEntryCase: String, CaseIterable {
        /// 戻り先は別フォルダーの別の文書。
        case otherDocument
        /// 戻り先は開いている文書のまま、表示中フォルダーだけが違う(フォルダー一覧から戻る)。
        case sameDocument
    }

    @Test("ファイルの履歴へ戻るとき、意図の遷移にフォルダーが現れない", arguments: [SidebarLayoutMode.tree, .drillDown], FileEntryCase.allCases)
    func goingBackToFileEntryNeverPresentsFolder(layout: SidebarLayoutMode, entry: FileEntryCase) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "HistoryPresentation.file.\(layout).\(entry)")
        let controller = fixture.controller
        defer { controller.close() }
        controller.switchFile(to: fixture.inOther) // 戻り先: other/t.md
        await controller.sidebar.awaitSettled()
        switch entry {
        case .otherDocument: controller.switchFile(to: fixture.deep)
        case .sameDocument: controller.navigateToFolder(fixture.sub)
        }
        await controller.sidebar.awaitSettled()
        let recorder = TargetRecorder(controller)

        controller.navigateHistory(by: -1)

        #expect(!controller.isPreviewingFolder, "一覧の着地前にフォルダー提示になった")
        await controller.sidebar.awaitSettled()
        #expect(!controller.isPreviewingFolder)
        #expect(controller.fileURL.normalizedPathKey == fixture.inOther.normalizedPathKey)
        #expect(!recorder.passedThroughFolder, "途中でフォルダー提示を通った: \(recorder.targets)")
        #expect(recorder.directoriesAtWrite.allSatisfy { $0.normalizedPathKey != fixture.other.normalizedPathKey })
    }

    /// 記録が一覧の着地を待っていた頃は、着地前に次の操作をすると世代の追い越しで
    /// 着地が捨てられ、フォルダーの訪問が履歴から落ちた。
    @Test("フォルダーに入って一覧の着地前にファイルを開いても、フォルダーの訪問が履歴に残る", arguments: [SidebarLayoutMode.tree, .drillDown])
    func folderVisitIsRecordedBeforeListingLands(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "HistoryPresentation.record.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }

        controller.navigateToFolder(fixture.other)
        controller.switchFile(to: fixture.deep) // other の一覧の着地を待たない
        await controller.sidebar.awaitSettled()
        controller.navigateHistory(by: -1)
        await controller.sidebar.awaitSettled()

        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.other))
    }

    /// 記録したフォルダーが消えていたら、その一覧ではなく開いている文書を出す(TASK-930.7 と
    /// 同じ規則。キー復帰を待つと、それまで失敗表示の一覧が残る)。
    @Test("消えたフォルダーの一覧の履歴へ戻ると、開いている文書を出す")
    func goingBackToVanishedFolderPresentsDocument() async throws {
        let fixture = try await makeFixture(layout: .drillDown, prefix: "HistoryPresentation.vanished")
        let controller = fixture.controller
        defer { controller.close() }
        controller.navigateToFolder(fixture.other)
        await controller.sidebar.awaitSettled()
        controller.switchFile(to: fixture.deep)
        await controller.sidebar.awaitSettled()
        try FileManager.default.removeItem(at: fixture.other)
        let recorder = TargetRecorder(controller)

        controller.navigateHistory(by: -1)

        #expect(controller.presentationIntent.target == PreviewTarget.file)
        #expect(!recorder.passedThroughFolder, "意図の遷移: \(recorder.targets)")
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == PreviewTarget.file)
    }
}
