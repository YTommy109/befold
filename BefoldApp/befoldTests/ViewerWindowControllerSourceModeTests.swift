import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ソース表示モードの復元・保持(DisplayModeStore 連携)を検証する unit テスト。
/// store に InMemoryFileReader + MockFileWatcher を注入する。
/// switchFile の存在ガードが store.fileReader 経由になった(TASK-116.12)ため、
/// 切替経由の復元・保持も InMemoryFileReader でモック化して unit で検証する。
/// コンテンツペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証はこのスイートに置かない。
@Suite
@MainActor
struct ViewerWindowControllerSourceModeTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/note.md")
    private let file1 = URL(fileURLWithPath: "/mock/first.md")
    private let file2 = URL(fileURLWithPath: "/mock/second.md")

    private func makeController(
        file: URL,
        extraFiles: [URL] = [],
        displayModeStore: DisplayModeStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, extraFiles: extraFiles, contents: "# hi",
            defaults: defaults, displayModeStore: displayModeStore
        ).controller
    }

    @Test("直接開いた場合も保存済みのソース表示モードが復元される")
    func openingFileDirectlyRestoresSavedSourceMode() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        displayModeStore.setDisplayMode(.source, for: file)

        let controller = makeController(file: file, displayModeStore: displayModeStore, defaults: defaults)
        defer { controller.close() }

        #expect(controller.isSourceMode)
    }

    @Test("switchFile は切替先ファイルの保存済みソース表示モードを復元する")
    func switchFileRestoresSavedSourceModeForTargetFile() {
        let controller = makeController(file: file1, extraFiles: [file2])
        defer { controller.close() }

        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)

        controller.switchFile(to: file2)
        // file2 は初めて開くファイルなのでレンダリング表示から始まる。
        #expect(!controller.isSourceMode)

        controller.switchFile(to: file1)
        // file1 に戻ると、以前トグルしたソース表示モードが復元される。
        #expect(controller.isSourceMode)
    }

    @Test("switchFile は旧・新ファイルの保存済みソース表示モードを破壊しない")
    func switchFilePreservesSavedSourceModeForBothFiles() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        displayModeStore.setDisplayMode(.source, for: file1)
        displayModeStore.setDisplayMode(.rendered, for: file2)
        let controller = makeController(
            file: file1, extraFiles: [file2], displayModeStore: displayModeStore, defaults: defaults
        )
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存済みモードが独立して保たれる。
        #expect(displayModeStore.displayMode(for: file1) == .source)
        #expect(displayModeStore.displayMode(for: file2) == .rendered)
    }

    /// AC#6: 差分表示もソース表示と同じくファイル単位で記憶する。
    /// 以前は差分だけアプリ全体の設定だったため、A で差分を選んで B へ移ると
    /// B はレンダリング表示なのに差分フラグだけ立っている状態になっていた。
    /// この粒度が壊れたらここが落ちる。
    @Test("差分表示はファイル単位で記憶され、別ファイルへ移っても引き継がれない")
    func diffModeIsRememberedPerFile() throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let swift1 = URL(fileURLWithPath: "/mock/first.swift")
        let swift2 = URL(fileURLWithPath: "/mock/second.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.diff")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        let controller = ViewerWindowControllerFixture(
            file: swift1, extraFiles: [swift2], contents: "let a = 1",
            defaults: defaults, displayModeStore: displayModeStore
        ).controller
        defer { controller.close() }
        controller.fileListModel.entries = [
            FileListEntry(url: swift1, kind: .file), FileListEntry(url: swift2, kind: .file),
        ]
        controller.fileListModel.selection = swift1

        controller.setDisplayMode(.diff)
        #expect(controller.isDiffShown)

        controller.switchFile(to: swift2)
        // swift2 は初めて開くファイルなので差分は引き継がれない。
        #expect(!controller.isDiffShown)
        #expect(displayModeStore.displayMode(for: swift2) == .rendered)

        controller.switchFile(to: swift1)
        // swift1 へ戻ると差分表示が復元される。
        #expect(controller.isDiffShown)
        #expect(displayModeStore.displayMode(for: swift1) == .diff)
    }

    /// TASK-368: プレビューを持たない種別(.code)は保存値が `.rendered` のままソースを出している。
    /// 遷移判定を保存値で行うと、選択済みの source セグメント・⌘2・パス無し `befold --source` が
    /// 遷移扱いになり、スクロール位置が rendered キーへ退避されたまま空の source キーから
    /// 復元されて先頭へ飛ぶ。判定を effectiveDisplayMode に寄せた結果がここで守られる。
    @Test("コード種別で選択済みの source を選び直しても遷移せず、保存値も書かれない")
    func selectingAlreadyShownSourceModeOnCodeFileIsNoOp() async {
        let code = URL(fileURLWithPath: "/mock/sample.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.code")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        let controller = ViewerWindowControllerFixture(
            file: code, contents: "let a = 1", defaults: defaults, displayModeStore: displayModeStore
        ).controller
        defer { controller.close() }
        // fileType はロード完了時に確定する。確定前は showsCodeContent が false で
        // effectiveDisplayMode も .rendered のままなので、再現条件が整うまで待つ。
        await waitForDeliveryOnMainActor { controller.store.showsCodeContent }

        // 保存値は .rendered のまま、表示は既にソース。
        #expect(controller.displayMode == .rendered)
        #expect(controller.effectiveDisplayMode == .source)

        controller.setDisplayMode(.source)

        #expect(controller.displayMode == .rendered)
        #expect(controller.effectiveDisplayMode == .source)
        // 意味の無い .source が永続化されていないこと(保存自体が起きていない)。
        #expect(defaults.dictionary(forKey: "ViewerDisplayModes") == nil)
    }

    /// 上の no-op 化が、コード種別からの正当な遷移まで塞いでいないことを押さえる。
    @Test("コード種別でも差分への遷移は従来どおり行われる")
    func selectingDiffModeOnCodeFileStillTransitions() throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let code = URL(fileURLWithPath: "/mock/sample.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.code")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        let controller = ViewerWindowControllerFixture(
            file: code, contents: "let a = 1", defaults: defaults, displayModeStore: displayModeStore
        ).controller
        defer { controller.close() }

        controller.setDisplayMode(.diff)

        #expect(controller.displayMode == .diff)
        #expect(displayModeStore.displayMode(for: code) == .diff)
    }

    /// TASK-370: cmd+U は「往復」であって「.source の指定」ではない。離脱側の cmd+U が
    /// 保存値を .rendered で上書きするため、戻り先を保存値から読むと必ず .source に落ち、
    /// そのファイルの .diff が永久に失われる。戻り先の記憶が壊れたらここが落ちる。
    @Test("差分表示中の cmd+U 往復で差分表示に戻り、保存値の .diff も残る")
    func toggleSourceViewRoundTripPreservesDiffMode() throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let code = URL(fileURLWithPath: "/mock/sample.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.roundTrip")
        let displayModeStore = DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        let controller = ViewerWindowControllerFixture(
            file: code, contents: "let a = 1", defaults: defaults, displayModeStore: displayModeStore
        ).controller
        defer { controller.close() }

        controller.setDisplayMode(.diff)
        #expect(controller.displayMode == .diff)

        controller.toggleSourceView(nil)
        #expect(controller.displayMode == .rendered)

        controller.toggleSourceView(nil)

        #expect(controller.displayMode == .diff)
        #expect(displayModeStore.displayMode(for: code) == .diff)
    }

    /// 戻り先の記憶はソース系モードへ入った時点で捨てる。捨てないと、往復の間に
    /// ⌘2 で source を選び直しても次の往復が差分へ戻ってしまう。
    @Test("往復の間に source を明示選択したら、その後の cmd+U は差分へ戻らない")
    func explicitSourceSelectionClearsRememberedDiffTarget() throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let code = URL(fileURLWithPath: "/mock/sample.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.clearTarget")
        let controller = ViewerWindowControllerFixture(
            file: code, contents: "let a = 1", defaults: defaults,
            displayModeStore: DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        ).controller
        defer { controller.close() }

        controller.setDisplayMode(.diff)
        controller.toggleSourceView(nil)
        controller.setDisplayMode(.source)
        controller.toggleSourceView(nil)
        #expect(controller.displayMode == .rendered)

        controller.toggleSourceView(nil)

        #expect(controller.displayMode == .source)
    }

    /// 記憶はファイル単位。別ファイルへ移った先で cmd+U が前のファイルの差分表示を
    /// 引き継がないこと(粒度が壊れたらここが落ちる)。
    @Test("cmd+U の戻り先は別ファイルへ引き継がれない")
    func rememberedToggleTargetDoesNotLeakAcrossFiles() throws {
        try #require(FeatureGate.isSourceDiffEnabled)
        let swift1 = URL(fileURLWithPath: "/mock/first.swift")
        let swift2 = URL(fileURLWithPath: "/mock/second.swift")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerSourceModeTests.leak")
        let controller = ViewerWindowControllerFixture(
            file: swift1, extraFiles: [swift2], contents: "let a = 1", defaults: defaults,
            displayModeStore: DisplayModeStore(defaults: defaults, isSourceDiffEnabled: true)
        ).controller
        defer { controller.close() }

        controller.setDisplayMode(.diff)
        controller.toggleSourceView(nil)
        controller.switchFile(to: swift2)
        #expect(controller.displayMode == .rendered)

        controller.toggleSourceView(nil)

        #expect(controller.displayMode == .source)
    }
}
