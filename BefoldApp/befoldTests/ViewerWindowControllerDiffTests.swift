import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

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

// 差分トグルの通知は MockViewerWindowControllerDelegate
// (ViewerWindowControllerTests.swift)で数える。反転と全ウィンドウへの反映は
// ViewerWindowManager の責務なので、コントローラ単体では「通知したか」で測る。

/// 差分表示のトグルが「いま何ができるか」(ViewerCapabilities)だけを見ていることを確かめる。
/// フォルダー一覧を出している間に効いてしまうと、見えていない文書に対する操作になる
/// (TASK-271 と同じ形の穴)。
///
/// ウィンドウ生成経路(共有インスタンスの配線・窓をまたぐ挙動)は
/// ViewerWindowManagerDiffTests が受け持つ。
@Suite
@MainActor
struct ViewerWindowControllerDiffTests {
    private let file = URL(fileURLWithPath: "/mock/note.swift")

    private func makeController(
        preference: DiffDisplayPreference, file: URL? = nil, diffReader: (any GitDiffReading)? = nil
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file ?? self.file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests"),
            diffDisplayPreference: preference,
            diffLoader: diffReader.map { GitDiffLoader(reader: $0) }
        ).controller
    }

    private func makePreference() -> DiffDisplayPreference {
        DiffDisplayPreference(defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests.pref"))
    }

    @Test("文書を提示している間は差分モードを選べる")
    func selectsDiffModeWhilePresentingDocument() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        controller.store.displayMode = .source
        // 前提そのものを固定する(能力が false のままだと、以下の切替は
        // 「効かなかった」のか「そもそも対象外だった」のか区別できない)。
        #expect(controller.capabilities.canSelectDiffMode)

        controller.setDisplayMode(.diff)

        #expect(controller.isDiffShown)
        #expect(controller.displayMode == .diff)
    }

    @Test("フォルダー提示中は差分モードもレイアウト切替も効かない")
    func ignoresDiffWhilePreviewingFolder() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        let folder = URL(fileURLWithPath: "/mock/sub")
        controller.fileListModel.entries = [
            FileListEntry(url: file, kind: .file),
            FileListEntry(url: folder, kind: .folder),
        ]
        controller.fileListModel.selection = folder
        controller.store.displayMode = .source
        #expect(!controller.capabilities.canSelectDiffMode)

        controller.setDisplayMode(.diff)
        controller.toggleDiffLayout(nil)

        #expect(controller.isPreviewingFolder)
        #expect(!controller.isDiffShown)
        #expect(preference.layout == .inline)
    }

    @Test("レイアウトはインラインと左右分割を往復する")
    func togglesLayoutBothWays() {
        let preference = makePreference()
        let controller = makeController(preference: preference)
        defer { controller.close() }
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        // レイアウトの切替は差分表示中だけ効く(AC#3)。
        controller.store.displayMode = .diff

        controller.toggleDiffLayout(nil)
        #expect(preference.layout == .sideBySide)

        controller.toggleDiffLayout(nil)
        #expect(preference.layout == .inline)
    }

    /// AC#2 / AC#3: バッジの更新契機(`.git/index` 変更・キーウィンドウ化・保存)は
    /// すべて git 状態の反映を通るため、そこに差分をぶら下げてある。
    /// git commit 後にコミット済みの差分が消えるのは、この経路が動くことに依存する。
    @Test("git 状態が反映されたら差分も取り直す")
    func refreshesDiffWhenGitStatusApplied() async {
        let preference = makePreference()
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "DiffTests.gitStatusApplied"),
            diffDisplayPreference: preference,
            // コミット後を模す。差分が無くなった結果を返す取得器を注入する。
            diffLoader: GitDiffLoader(reader: StubDiffReader(result: .noChanges)),
            gitFileIndex: SlowRootGitFileIndex(delay: 0)
        ).controller
        defer { controller.close() }
        presentDocument(in: controller, file: file)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        // SidebarNavigator が git 状態を反映したときに呼ぶ経路(protocol 必須メソッド)。
        controller.gitStatusDidApply()

        // 取得は detached の utility タスクを経由するため、全スイート並列実行では
        // 協調スレッドの空き待ちで数秒かかる(単体では 0.2 秒)。既定の 10 秒では足りない。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.diffText == nil
        }
    }

    /// 差分表示モードでなければ git を起こさない。契機がバッジと同数へ増えたため、
    /// 表示側で捨てるだけでは `.git` の書き込みごとに subprocess が走る。
    /// 併せて、差分表示を離れたときに取得済みの本文が捨てられることも測る(開始時の無効化)。
    @Test("差分表示モードでなければ取得しない")
    func skipsFetchWhenNotInDiffMode() {
        let preference = makePreference()
        let reader = RecordingDiffReader()
        let controller = makeController(preference: preference, diffReader: reader)
        defer { controller.close() }
        presentDocument(in: controller, file: file)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        controller.setDisplayMode(.source)

        #expect(!controller.isDiffShown)
        #expect(controller.store.diffText == nil)
        controller.refreshDiff()
        #expect(reader.callCount == 0)
        #expect(controller.store.diffText == nil)
    }

    /// CSV/TSV は文書を提示していてソース表示中でも差分を描けない(viewer 側が
    /// type === "csv" で空を返す)。ここが true に戻ると、⌘D はチェックだけ付いて
    /// 表示は変わらないまま、保存のたびに git のサブプロセスが走る(TASK-324)。
    @Test("CSV のソース表示では差分を取得しない")
    func skipsFetchForCSVSourceView() async {
        let csv = URL(fileURLWithPath: "/mock/table.csv")
        let preference = makePreference()
        let reader = RecordingDiffReader()
        let controller = makeController(preference: preference, file: csv, diffReader: reader)
        defer { controller.close() }
        presentDocument(in: controller, file: csv)
        // 種別は読み込み完了時に確定する。ここを待たないと既定の .mmd のまま測ってしまい、
        // canToggleDiff が false でも「CSV だから」ではなくなる。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.fileType == .csv(delimiter: ",")
        }
        #expect(controller.store.showsCodeContent)
        #expect(!controller.capabilities.canSelectDiffMode)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        controller.refreshDiff()

        #expect(reader.callCount == 0)
        #expect(controller.store.diffText == nil)
    }

    /// 種別ゲート(CSV/TSV)は切替**先**のファイルで判定する。`store.fileType` は
    /// 非同期のコンテンツロード完了まで旧ファイルの値を保つため、それを見ていると
    /// 切替直後に届いた取得契機(`.git/index` 変更・他ウィンドウの保存)が旧ファイルの
    /// 種別でゲートを通り、CSV に対して git を起こしてしまう(TASK-338)。
    @Test("ファイル切替直後の取得契機でも切替先の種別でゲートする")
    func gatesByDestinationFileTypeDuringSwitch() async {
        let csv = URL(fileURLWithPath: "/mock/table.csv")
        let preference = makePreference()
        let reader = RecordingDiffReader()
        let controller = ViewerWindowControllerFixture(
            file: file, extraFiles: [csv], contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "DiffTests.switchGate"),
            diffDisplayPreference: preference,
            diffLoader: GitDiffLoader(reader: reader),
            // 既定の索引は /mock 配下でリポジトリルートを返さず、取得へ到達しない。
            gitFileIndex: SlowRootGitFileIndex(delay: 0)
        ).controller
        defer { controller.close() }
        presentDocument(in: controller, file: file)
        // 前提: 切替前の .swift のロードが確定し、差分を出せる状態になっている。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.filePath == file
        }
        #expect(controller.capabilities.canSelectDiffMode)

        // 切替直後(ロード確定前)に取得契機が届く状況を作る。
        controller.performFileSwitch(to: csv)
        #expect(controller.fileURL == csv)
        // CSV 側もソース表示で開く(保存済みの表示モードが ON のケース)。
        controller.store.displayMode = .source
        // 種別はまだ旧ファイルのもの = ここが「すり抜け」の入口。
        #expect(controller.store.fileType.supportsDiffDisplay)
        controller.gitStatusDidApply()

        // ロードが確定しても取得が起きないことまで見る(確定後は fileType 経由でも弾かれる
        // ため、確定前の 1 回を取りこぼさないよう待ってから測る)。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.fileType == .csv(delimiter: ",")
        }
        // 測るのは「切替先へ git を起こしたか」であって取得の総数ではない。総数で測ると、
        // 切替前の .swift に対する正当な取得まで数えてしまい、その回数は契機の重なり方で
        // 変わるため結論が実行順に左右される(TASK-347)。
        #expect(reader.requestedFiles.contains(csv) == false)
    }

    /// Markdown/SVG/HTML は「ソース表示中」でないと差分を描けないため、レンダリング表示中の
    /// refreshDiff は取得せず diffText を捨てる。モード切替が差分の取り直しを起こさないと、
    /// ソース表示へ切り替えても差分が出ず、保存・`.git/index` 変更など無関係な契機が
    /// 来るまで素のソースのままになる(TASK-337)。
    @Test("差分表示へ切り替えたら差分を取り直す")
    func refreshesDiffWhenSwitchingToDiffMode() async {
        let markdown = URL(fileURLWithPath: "/mock/note.md")
        let preference = makePreference()
        let reader = RecordingDiffReader()
        let controller = ViewerWindowControllerFixture(
            file: markdown, contents: "# note",
            defaults: makeIsolatedDefaults(prefix: "DiffTests.sourceModeSwitch"),
            diffDisplayPreference: preference,
            diffLoader: GitDiffLoader(reader: reader),
            // 既定の索引は /mock 配下でリポジトリルートを返さず、取得へ到達しない。
            gitFileIndex: SlowRootGitFileIndex(delay: 0)
        ).controller
        defer { controller.close() }
        // presentDocument は差分表示にしてしまうため、提示状態だけを作る
        // (レンダリング表示のまま切り替えることがこのテストの前提)。
        controller.fileListModel.entries = [FileListEntry(url: markdown, kind: .file)]
        controller.fileListModel.selection = markdown
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controller.store.fileType == .markdown
        }
        // 前提: レンダリング表示中は差分モードを選んでいない = ここでは取得も起きない。
        #expect(!controller.isDiffShown)
        controller.refreshDiff()
        #expect(reader.callCount == 0)

        controller.setDisplayMode(.diff)

        #expect(controller.isDiffShown)
        // 測るのは「取り直しが起きたか」。回数は固定しない。ソース表示への切替と
        // git 状態の反映が別のターンに分かれると、それぞれが別の契機として取得を起こす
        // （契機ごとに読み直すのは仕様。合流するのは同じ契機の兄弟要求だけ = TASK-346）。
        // 回数で測ると、契機がどう重なったかで結論が変わる（CI で実際に落ちた = TASK-348）。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            reader.callCount > 0
        }
    }

    /// ルート解決は差分取得と同じく git のサブプロセスを起こしうるため、メインアクター上で
    /// 同期に呼ぶとコンテンツ再読込のたびに UI が止まる。refreshDiff がすぐ戻ることで測る。
    @Test("差分の取り直しはリポジトリルート解決でメインアクターを止めない")
    func refreshDiffDoesNotBlockMainActorOnRootResolution() {
        let preference = makePreference()
        let delay: TimeInterval = 0.5
        let controller = ViewerWindowControllerFixture(
            file: file, contents: "let a = 1",
            defaults: makeIsolatedDefaults(prefix: "ViewerWindowControllerDiffTests.slowRoot"),
            diffDisplayPreference: preference,
            // 機能ゲートが無効なビルドでは既定の diffLoader が nil で、refreshDiff が
            // ルート解決へ到達しない(それでは何も測れない)。取得器を明示的に注入する。
            diffLoader: GitDiffLoader(reader: StubDiffReader(result: .noChanges)),
            gitFileIndex: SlowRootGitFileIndex(delay: delay)
        ).controller
        defer { controller.close() }

        let started = Date()
        controller.refreshDiff()
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < delay / 2)
    }
}
