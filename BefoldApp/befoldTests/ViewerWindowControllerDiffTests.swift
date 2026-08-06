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

/// 呼び出し回数だけを数える取得器。「取得そのものを走らせない」ことの検証に使う。
private final class RecordingDiffReader: GitDiffReading, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }; return calls
    }

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return .noChanges
    }
}

/// 差分トグルの通知だけを数える delegate。反転と全ウィンドウへの反映は
/// ViewerWindowManager の責務なので、コントローラ単体では「通知したか」で測る。
@MainActor
private final class RecordingDiffToggleDelegate: ViewerWindowControllerDelegate {
    private(set) var toggleSourceDiffCallCount = 0

    func viewerWindowWillClose(_ controller: ViewerWindowController) {}
    func viewerWindowDidBecomeKey(_ controller: ViewerWindowController) {}
    func viewerWindow(_ controller: ViewerWindowController, didRenameFrom oldURL: URL, to newURL: URL) {}
    func viewerWindow(
        _ controller: ViewerWindowController, didSwitchFileFrom oldURL: URL, to newURL: URL
    ) {}
    func viewerWindowDidToggleHiddenFiles(_ controller: ViewerWindowController) {}
    func viewerWindowDidToggleChangedFilesOnly(_ controller: ViewerWindowController) {}

    func viewerWindowDidToggleSourceDiff(_ controller: ViewerWindowController) {
        toggleSourceDiffCallCount += 1
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
        let delegate = RecordingDiffToggleDelegate()
        controller.delegate = delegate
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.isSourceMode = true
        // 前提そのものを固定する(能力が false のままだと、以下のトグルは
        // 「効かなかった」のか「そもそも対象外だった」のか区別できない)。
        #expect(controller.capabilities.canToggleDiff)

        controller.toggleSourceDiff(nil)

        // 反転そのものは ViewerWindowManager が全ウィンドウまとめて行う(TASK-330)。
        // ここで自分だけ反転すると他ウィンドウが取り直さないため、通知だけを確かめる。
        #expect(delegate.toggleSourceDiffCallCount == 1)
        #expect(preference.isEnabled == false)
    }

    @Test("フォルダー提示中はトグルが効かない")
    func ignoresToggleWhilePreviewingFolder() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        let delegate = RecordingDiffToggleDelegate()
        controller.delegate = delegate
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
        #expect(delegate.toggleSourceDiffCallCount == 0)
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
    /// 反転は ViewerWindowManager 経由なので、そこから駆動して確かめる。
    @Test("差分表示を OFF にすると本文が捨てられる")
    func clearsDiffTextWhenDisabled() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "DiffTests.clear")
        defer { fixture.closeAll() }
        fixture.diffDisplayPreference.isEnabled = true
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.allControllers.first)
        presentDocument(in: controller)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        fixture.manager.toggleSourceDiff()

        #expect(fixture.diffDisplayPreference.isEnabled == false)
        #expect(controller.store.diffText == nil)
    }

    /// AC#1: 共有設定なので、片方のウィンドウの ⌘D は他方の差分まで取り直させる。
    /// 反転したウィンドウだけが取り直すと、他方はメニューのチェックだけ変わる(TASK-330)。
    @Test("片方のウィンドウのトグルが全ウィンドウの差分に届く")
    func toggleReachesEveryWindow() async {
        let first = URL(fileURLWithPath: "/mock/first.swift")
        let second = URL(fileURLWithPath: "/mock/second.swift")
        let fixture = MockedViewerWindowManager(
            files: [first, second], prefix: "DiffTests.broadcast",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock")
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        for controller in controllers {
            presentDocument(in: controller, file: controller.fileURL)
            controller.diffLoader = GitDiffLoader(reader: StubDiffReader(result: .diff("DIFF")))
        }

        // 1 枚目のウィンドウのメニュー操作(⌘D)を再現する。
        controllers[0].toggleSourceDiff(nil)

        #expect(fixture.diffDisplayPreference.isEnabled)
        // 2 窓ぶんの取得が detached の utility タスクを経由する(上記と同じ理由で長めに待つ)。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controllers.allSatisfy { $0.store.diffText == "DIFF" }
        }
    }

    /// AC#2 / AC#3: バッジの更新契機(`.git/index` 変更・キーウィンドウ化・保存)は
    /// すべて git 状態の反映を通るため、そこに差分をぶら下げてある。
    /// git commit 後にコミット済みの差分が消えるのは、この経路が動くことに依存する。
    @Test("git 状態が反映されたら差分も取り直す")
    func refreshesDiffWhenGitStatusApplied() async {
        let preference = makePreference()
        preference.isEnabled = true
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "DiffTests.gitStatusApplied"),
            diffDisplayPreference: preference,
            gitFileIndex: SlowRootGitFileIndex(delay: 0)
        ).controller
        defer { controller.close() }
        presentDocument(in: controller)
        // コミット後を模す。差分が無くなった結果を返す取得器へ差し替える。
        controller.diffLoader = GitDiffLoader(reader: StubDiffReader(result: .noChanges))
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        // SidebarNavigator が git 状態を反映したときに呼ぶ経路(protocol 必須メソッド)。
        controller.gitStatusDidApply()

        // 取得は detached の utility タスクを経由するため、全スイート並列実行では
        // 協調スレッドの空き待ちで数秒かかる(単体では 0.2 秒)。既定の 10 秒では足りない。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.diffText == nil
        }
    }

    /// 差分を描けない種別(画像・PDF など)では git を起こさない。契機がバッジと同数へ
    /// 増えたため、表示側で捨てるだけでは `.git` の書き込みごとに subprocess が走る。
    @Test("差分を出せない状態では取得しない")
    func skipsFetchWhenDiffCannotBeShown() {
        let preference = makePreference()
        preference.isEnabled = true
        let controller = makeController(preference: preference)
        defer { controller.close() }
        // 文書を提示していない(= canToggleDiff が false)状態。
        #expect(!controller.capabilities.canToggleDiff)
        let reader = RecordingDiffReader()
        controller.diffLoader = GitDiffLoader(reader: reader)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        controller.refreshDiff()

        #expect(reader.callCount == 0)
        #expect(controller.store.diffText == nil)
    }

    /// トグルできる状態(文書を提示していて選択も現在ファイル)を作る。
    private func presentDocument(in controller: ViewerWindowController, file: URL? = nil) {
        let file = file ?? self.file
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.isSourceMode = true
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

        let enabled = controllers.filter(\.isDiffShown)
        #expect(enabled.count == controllers.count)
        let shared = controllers.filter { $0.diffDisplayPreference === fixture.diffDisplayPreference }
        #expect(shared.count == controllers.count)
    }
}
