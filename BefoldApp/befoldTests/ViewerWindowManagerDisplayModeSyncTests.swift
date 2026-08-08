import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 同一ファイルを複数ウィンドウで開いたときに表示モードが揃うか(TASK-371)。
///
/// 不変条件は「同一ファイルを表示している窓は同じ表示モードを示す」で、対象は
/// **永続化されるユーザー選択**に限る(CLI `--source`/`--preview` のこの起動限りの上書きは
/// 意図的に窓ごと)。この担保が無いと、片方の窓だけが差分表示になり、再起動後は
/// last-write-wins で両窓が差分になって終了前の画面と食い違う。
///
/// 差分の着地待ちは壁時計予算を持たない `waitForDeliveryOnMainActor` で行う
/// (予算付きのポーリングは full suite で順番待ちの時間を測ってしまう = TASK-354)。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowManagerDisplayModeSyncTests {
    private let shared = URL(fileURLWithPath: "/mock/shared.swift")
    private let other = URL(fileURLWithPath: "/mock/other.swift")

    /// 同一ファイルを 2 窓に並べる。`openViewer` は同じファイルの重複ウィンドウを作らない
    /// (既存を前面化する)ため、2 窓目は別ファイルで開いてからウィンドウ内で切り替える。
    /// 実際に同一ファイルが 2 窓へ並ぶのもこの経路で、`controllers` のキー付け替えも踏む。
    private func openTwoWindowsOnSharedFile(
        _ fixture: MockedViewerWindowManager, mode: ViewerDisplayMode
    ) throws -> (origin: ViewerWindowController, peer: ViewerWindowController) {
        fixture.manager.openViewer(for: shared)
        fixture.manager.openViewer(for: other)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        let peer = try #require(controllers.first { $0.fileURL == other })
        peer.switchFile(to: shared)
        #expect(controllers.allSatisfy { $0.fileURL == shared })
        for controller in controllers {
            // フォルダー一覧ではなく文書を提示している状態にする(capabilities の前提)。
            controller.fileListModel.entries = [FileListEntry(url: shared, kind: .file)]
            controller.fileListModel.selection = shared
            controller.store.displayMode = mode
        }
        return try (#require(controllers.first { $0 !== peer }), peer)
    }

    /// AC#1 / AC#3: 片方の窓で差分を選ぶと、同じファイルを表示しているもう片方も差分になる。
    /// broadcast を落とすと、選んでいない窓が plain source のまま残ってここが落ちる。
    @Test("同一ファイルを 2 窓で開くと差分表示の選択が両方へ反映される")
    func mirrorsDiffModeAcrossWindowsShowingTheSameFile() async throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DisplayModeSync.diff",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .source)

        // 1 枚目のウィンドウのメニュー操作(⌘3)を再現する。
        origin.setDisplayMode(.diff)

        #expect(origin.isDiffShown)
        #expect(peer.isDiffShown)
        // 反映された窓も差分本文を受け取る。モードだけ移して取り直さないと、
        // 差分表示のはずの窓が空のまま plain source と同じ見た目になる。
        await waitForDeliveryOnMainActor {
            peer.store.diffText == "DIFF"
        }
    }

    /// AC#1: 反映は差分に限らない。差分を選べないビルド・種別でも成立させたいので、
    /// 機能ゲートに依存しない `.source` でも同じ経路が働くことを別に固定する
    /// (`diffLoader` はゲート OFF で nil になるため、差分だけで測ると片側しか検証されない)。
    @Test("同一ファイルを 2 窓で開くとソース表示の選択も両方へ反映される")
    func mirrorsSourceModeAcrossWindowsShowingTheSameFile() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DisplayModeSync.source", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .rendered)

        origin.setDisplayMode(.source)

        #expect(origin.effectiveDisplayMode == .source)
        #expect(peer.effectiveDisplayMode == .source)
    }

    /// AC#2: 別ファイルを表示している窓は影響を受けない。対象は `controllers` のキー引きで
    /// 求めるため、`allControllers` へ配る形に戻すとここが落ちる。
    @Test("別ファイルを表示しているウィンドウは表示モードの反映を受けない")
    func doesNotMirrorToWindowsShowingAnotherFile() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DisplayModeSync.otherFile", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: shared)
        fixture.manager.openViewer(for: other)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        for controller in controllers {
            controller.fileListModel.entries = [FileListEntry(url: controller.fileURL, kind: .file)]
            controller.fileListModel.selection = controller.fileURL
            controller.store.displayMode = .rendered
        }
        let origin = try #require(controllers.first { $0.fileURL == shared })
        let untouched = try #require(controllers.first { $0.fileURL == other })

        origin.setDisplayMode(.source)

        #expect(origin.effectiveDisplayMode == .source)
        #expect(untouched.effectiveDisplayMode == .rendered)
    }

    /// cmd+U の戻り先の記憶は窓ごとの操作履歴であり、同期しないと決めた
    /// (`ViewerWindowController.mirrorDisplayMode` の doc コメント)。記憶まで配ると
    /// 「操作していない窓の cmd+U が、その窓では離れていないモードへ戻る」になる。
    ///
    /// 記憶を配る実装へ変えると、最後の cmd+U が差分へ戻ってここが落ちる。
    @Test("cmd+U の戻り先の記憶は窓ごとで、反映を受けた窓は既定のソース表示へ戻る")
    func doesNotMirrorSourceToggleReturnMemory() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DisplayModeSync.toggleReturn",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .source)
        origin.setDisplayMode(.diff)
        #expect(peer.isDiffShown)

        // 操作した窓が cmd+U でレンダリング表示へ離れる。反映を受けた窓も一緒に離れる。
        origin.toggleSourceView(nil)
        #expect(origin.effectiveDisplayMode == .rendered)
        #expect(peer.effectiveDisplayMode == .rendered)

        // 反映を受けた側の cmd+U は、自分が離れたわけではないので差分ではなくソース表示へ戻る。
        peer.toggleSourceView(nil)

        #expect(peer.effectiveDisplayMode == .source)
        #expect(!peer.isDiffShown)
        // 操作した窓は反映を受けて同じモードへ揃う(不変条件はここでも保たれる)。
        #expect(origin.effectiveDisplayMode == .source)
    }
}
