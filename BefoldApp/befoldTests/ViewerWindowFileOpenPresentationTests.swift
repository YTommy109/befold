import AppKit
@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ファイルを開く経路では、サイドバーの同期がどの段階にあっても本文がフォルダー一覧に
/// ならないことを検証する(ADR 0013 / TASK-930.1 / GitHub #794)。
///
/// サイドバーの行は非同期に届く(一覧の取り直し・ツリーの子リスト)。本文の提示を行の有無から
/// 導いていた頃は、行が届くまでの間に `.folder` へ倒れ、本文に一覧が重なった。ここでは
/// 切り替えの直後(同期区間 = 子リストの着地前)と着地後の両方で `isPreviewingFolder` を見る。
/// 同期区間の中だけで起きる一瞬の `.folder` は値を後から読んでも見えないため、意図が
/// 通った値を全部記録し、フォルダー提示を一度も通らないことも確かめる。
///
/// 修正前(提示をサイドバーの選択と行から導いていた頃)の実測: ツリーで畳まれた
/// サブフォルダー内・同じフォルダーの行の無いファイル(リストでは着地後も残る)・名前変更の
/// 3 経路で、本文がフォルダー提示になった(当時はタイトルの KVO で記録した)。
@Suite
@MainActor
struct ViewerWindowFileOpenPresentationTests {
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
        let manager = FileManager.default
        let base = tmp.url.appendingPathComponent("base", isDirectory: true)
        let sub = base.appendingPathComponent("sub", isDirectory: true)
        let other = tmp.url.appendingPathComponent("other", isDirectory: true)
        for dir in [sub, other] {
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
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

    /// 本文の意図が通った値をすべて記録する。窓の再同期(`onChange` の既存の配線)は
    /// そのまま呼ぶので、記録のために本番の挙動を変えない。
    @MainActor
    private final class TargetRecorder {
        private(set) var targets: [PreviewTarget] = []

        init(_ controller: ViewerWindowController) {
            let intent = controller.presentationIntent
            let original = intent.onChange
            intent.onChange = { [weak self, weak intent] in
                if let intent { self?.targets.append(intent.target) }
                original?()
            }
        }

        var passedThroughFolder: Bool {
            targets.contains { $0.folderURL != nil }
        }
    }

    @Test("畳まれたサブフォルダー内のファイルへ切り替えても、本文はフォルダー一覧にならない", arguments: [SidebarLayoutMode.tree, .drillDown])
    func switchIntoCollapsedSubfolderKeepsDocument(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "FileOpenPresentation.deep.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        let recorder = TargetRecorder(controller)

        controller.switchFile(to: fixture.deep)
        #expect(!controller.isPreviewingFolder, "子リストの着地前にフォルダー提示になった")
        await controller.sidebar.awaitSettled()

        #expect(!controller.isPreviewingFolder)
        #expect(!recorder.passedThroughFolder, "途中でフォルダー提示を通った: \(recorder.targets)")
    }

    @Test("別フォルダーのファイルへ切り替えても、本文はフォルダー一覧にならない", arguments: [SidebarLayoutMode.tree, .drillDown])
    func switchIntoOtherFolderKeepsDocument(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "FileOpenPresentation.other.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        let recorder = TargetRecorder(controller)

        controller.switchFile(to: fixture.inOther)
        #expect(!controller.isPreviewingFolder, "一覧の着地前にフォルダー提示になった")
        await controller.sidebar.awaitSettled()

        #expect(!controller.isPreviewingFolder)
        #expect(!recorder.passedThroughFolder, "途中でフォルダー提示を通った: \(recorder.targets)")
    }

    /// 一覧を取った後に作られたファイルには行が無い。親フォルダーは表示中のままなので、
    /// サイドバーは移動も取り直しもしない。
    @Test("同じフォルダーの、一覧に行の無いファイルへ切り替えても、本文はフォルダー一覧にならない", arguments: [SidebarLayoutMode.tree, .drillDown])
    func switchToUnlistedSiblingKeepsDocument(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "FileOpenPresentation.unlisted.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        let fresh = fixture.base.appendingPathComponent("fresh.md")
        try Data("# y".utf8).write(to: fresh)
        let recorder = TargetRecorder(controller)

        controller.switchFile(to: fresh)
        #expect(!controller.isPreviewingFolder, "行の無いファイルでフォルダー提示になった")
        await controller.sidebar.awaitSettled()

        #expect(!controller.isPreviewingFolder)
        #expect(!recorder.passedThroughFolder, "途中でフォルダー提示を通った: \(recorder.targets)")
    }

    /// 名前変更の取り直しは、一覧(新しい行)を選択(旧 URL)より先に書く。
    @Test("開いているファイルの名前を変えても、取り直しの着地で本文がフォルダー一覧を通らない", arguments: [SidebarLayoutMode.tree, .drillDown])
    func renameKeepsDocument(layout: SidebarLayoutMode) async throws {
        let fixture = try await makeFixture(layout: layout, prefix: "FileOpenPresentation.rename.\(layout)")
        let controller = fixture.controller
        defer { controller.close() }
        let old = fixture.base.appendingPathComponent("a.md")
        let renamed = fixture.base.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: old, to: renamed)
        let recorder = TargetRecorder(controller)

        // 本番では ViewerStore が現在 URL を新パスへ進めてから controller.handleRename を呼ぶ。
        controller.store.openFile(renamed)
        controller.handleRename(from: old, to: renamed)
        await controller.sidebar.awaitSettled()

        #expect(!controller.isPreviewingFolder)
        #expect(!recorder.passedThroughFolder, "途中でフォルダー提示を通った: \(recorder.targets)")
    }

    /// サイドバーの同期処理は本文の意図を書かない(ADR 0013 決定 3)。フォルダー一覧・文書の
    /// どちらを出していても、取り直し・表示形式の切り替え・不可視ファイルの切り替え・
    /// 折りたたみの後で本文は変わらない。
    @Test(
        "サイドバーの同期処理は、本文に出しているものを変えない",
        arguments: [PreviewTarget.file, .folder(URL(fileURLWithPath: "/"))]
    )
    func sidebarSyncNeverChangesPresentation(initial: PreviewTarget) async throws {
        let fixture = try await makeFixture(layout: .tree, prefix: "FileOpenPresentation.sync.\(initial)")
        let controller = fixture.controller
        defer { controller.close() }
        // フォルダー一覧の場合は、実在するサブフォルダーを利用者が選んだ状態から始める。
        let expected: PreviewTarget = initial.folderURL == nil ? .file : .folder(fixture.sub)
        if case let .folder(url) = expected { controller.fileListDidSelectFolder(url) }
        controller.sidebar.expandFolder(fixture.sub.normalizedPathKey, at: fixture.sub)
        await controller.sidebar.awaitSettled()

        controller.sidebar.refreshFileList()
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == expected, "取り直しで変わった")
        controller.sidebar.collapseFolder(fixture.sub.normalizedPathKey)
        #expect(controller.presentationIntent.target == expected, "折りたたみで変わった")
        controller.sidebar.applyDisplayChange(.toggleHiddenFiles)
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == expected, "不可視ファイルの切り替えで変わった")
        controller.sidebar.applyDisplayChange(.toggleLayoutMode)
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == expected, "表示形式の切り替えで変わった")
    }

    // MARK: - フォルダー一覧の表示中にファイルを開く経路(TASK-930.2)

    /// 窓の中でファイルを開く経路。どれも `performFileSwitch` に集まり、そこが本文の読み込みと
    /// サイドバーの同期より先に `.file` を書く(ADR 0013 決定 4)。Quick Open・本文の一覧・
    /// スライドの前後移動は `switchFile(to:)` をそのまま呼ぶ(`QuickOpenCoordinator.open` /
    /// `ViewerWindowAssembler.makeSplitViewController` の `onSelectFile` /
    /// `moveToAdjacentFile`)ので、`switchFile` の経路で代表させる。
    enum OpenPath: String, CaseIterable {
        case quickOpen, sidebarFileRow, link, historyBack
    }

    @Test("フォルダー一覧の表示中にどの経路でファイルを開いても、本文は文書の提示 1 回だけで移る", arguments: OpenPath.allCases)
    func openingFileFromFolderListingPresentsDocumentOnce(path: OpenPath) async throws {
        let fixture = try await makeFixture(layout: .tree, prefix: "FileOpenPresentation.path.\(path.rawValue)")
        let controller = fixture.controller
        defer { controller.close() }
        if path == .historyBack {
            // 戻り先の文書エントリを積んでおく(a.md → t.md と開き、a.md へ戻る)。
            controller.switchFile(to: fixture.inOther)
            await controller.sidebar.awaitSettled()
        }
        controller.fileListDidSelectFolder(fixture.sub)
        #expect(controller.isPreviewingFolder)
        let recorder = TargetRecorder(controller)

        switch path {
        case .quickOpen: controller.switchFile(to: fixture.deep)
        case .sidebarFileRow: controller.fileListDidSelectFile(fixture.deep)
        case .link: controller.openReference(fixture.deep, disposition: .currentTab)
        case .historyBack: controller.navigateHistory(by: -1)
        }
        await controller.sidebar.awaitSettled()

        #expect(recorder.targets == [.file], "意図の遷移: \(recorder.targets)")
        #expect(!controller.isPreviewingFolder)
    }
}

// MARK: - Folder Entry

extension ViewerWindowFileOpenPresentationTests {
    /// フォルダーに入る・上へ移動すると、本文には移動先の一覧が出て、開いている文書は
    /// 変わらない(ADR 0013 決定 5 / TASK-930.3)。かつては先頭行(other なら t.md)を
    /// 自動で開き、上へ移動では直前にいた子フォルダーの一覧を出していた。
    @Test("リスト表示でフォルダーに入る・上へ移動すると、移動先の一覧を出し文書は切り替えない")
    func enteringOrLeavingFolderPresentsDestinationListing() async throws {
        let fixture = try await makeFixture(layout: .drillDown, prefix: "FileOpenPresentation.enter")
        let controller = fixture.controller
        defer { controller.close() }
        let opened = controller.fileURL

        controller.navigateToFolder(fixture.other) // 先頭行は t.md(ファイル)
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.other))
        #expect(controller.fileURL == opened)

        controller.navigateToFolder(fixture.sub)
        await controller.sidebar.awaitSettled()
        controller.navigateToFolder(fixture.base) // 上へ移動
        await controller.sidebar.awaitSettled()
        #expect(controller.presentationIntent.target == PreviewTarget.folder(fixture.base))
        #expect(controller.fileURL == opened)
    }
}
