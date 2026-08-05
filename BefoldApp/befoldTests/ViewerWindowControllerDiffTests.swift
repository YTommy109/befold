import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 差分表示のトグルが「いま何ができるか」(ViewerCapabilities)だけを見ていることを確かめる。
/// フォルダー一覧を出している間に効いてしまうと、見えていない文書に対する操作になる
/// (TASK-271 と同じ形の穴)。
/// ルート解決に時間がかかる索引。`git rev-parse` のサブプロセスが遅い状況
/// (ネットワークボリューム・応答しない git)を、実 git を起こさずに作る。
private final class SlowRootGitFileIndex: GitFileIndexing, @unchecked Sendable {
    private let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }

    /// `repositoryRoot(forDirectoryAt:)` はプロトコル拡張だけの実装（静的ディスパッチ）で、
    /// ここで上書きしても `any GitFileIndexing` 越しには呼ばれない。プロトコル要件である
    /// こちらを遅くすることで、拡張経由の解決も遅くなる。
    func repositoryRoot(forFileAt url: URL) -> URL? {
        Thread.sleep(forTimeInterval: delay)
        return url.deletingLastPathComponent()
    }
}

/// 常に同じ結果を返す取得器。git は起こさない。
private struct StubDiffReader: GitDiffReading {
    let result: GitFileDiff?

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        result
    }
}

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

    /// ルート解決は差分取得と同じく git のサブプロセスを起こしうるため、メインアクター上で
    /// 同期に呼ぶとコンテンツ再読込のたびに UI が止まる。refreshDiff がすぐ戻ることで測る。
    @Test("差分の取り直しはリポジトリルート解決でメインアクターを止めない")
    func refreshDiffDoesNotBlockMainActorOnRootResolution() {
        let preference = makePreference()
        preference.isEnabled = true
        let delay: TimeInterval = 0.5
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests.slowRoot"),
            diffDisplayPreference: preference,
            gitFileIndex: SlowRootGitFileIndex(delay: delay)
        ).controller
        defer { controller.close() }
        // 機能ゲートが無効なビルドでは diffLoader が nil で、refreshDiff が
        // ルート解決へ到達しない(それでは何も測れない)。取得器を明示的に注入する。
        controller.diffLoader = GitDiffLoader(reader: StubDiffReader(result: .noChanges))

        let started = Date()
        controller.refreshDiff()
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < delay / 2)
    }

    /// 生成経路(ViewerWindowManager)が共有インスタンスを渡していることの固定。
    /// 窓をまたぐ設定なのでコントローラ単体テストでは捕まえられない。
    @Test("生成したウィンドウは差分表示設定を共有する")
    func openViewerSharesDiffDisplayPreference() {
        let first = URL(fileURLWithPath: "/mock/first.swift")
        let second = URL(fileURLWithPath: "/mock/second.swift")
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)

        // 共有インスタンスを動かして観測する。メニュー操作(toggleSourceDiff)経由だと
        // フィーチャーゲート無効時に両方 false のまま一致し、共有していなくても通る。
        fixture.diffDisplayPreference.isEnabled = true

        let enabled = controllers.filter(\.isSourceDiffEnabled)
        #expect(enabled.count == controllers.count)
        let shared = controllers.filter { $0.diffDisplayPreference === fixture.diffDisplayPreference }
        #expect(shared.count == controllers.count)
    }
}
