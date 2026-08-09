import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 文書の状態(表示モード・ズーム倍率・スクロール位置)が窓ごとに独立していることを固定する
/// (ADR 0002「複数ウィンドウでの扱い」/「文書の状態の規則」・TASK-388)。
///
/// 規則は 2 つで、このスイートはその両方が破れたら落ちる。
///
/// - 窓間の同期はしない。同じファイルを 2 窓で別々のモード・倍率・位置で読むのは正常な使い方
///   (TASK-371 で入れた `mirrorDisplayMode` 経由の同期を撤去した)
/// - ファイル単位の保存値を読むのは、窓がその文書を**提示し始めるとき**だけ。生きている窓が
///   読み直すと、他窓の操作が後から効いてしまう
///
/// 前身は ViewerWindowManagerDisplayModeSyncTests で、同期する側を担保していた。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowStateIndependenceTests {
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

    /// AC#1 / AC#3: 片方の窓で差分を選んでも、もう片方は選ぶ前のモードのまま。
    /// デリゲート通知と `mirrorDisplayMode` を戻すと、操作していない窓まで差分になって落ちる。
    @Test("同一ファイルを 2 窓で開いても、差分表示の選択は選んだ窓だけに効く")
    func doesNotMirrorDiffModeToOtherWindows() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DocumentStateIndependence.diff",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .source)

        // 1 枚目のウィンドウのメニュー操作(⌘3)を再現する。
        origin.setDisplayMode(.diff)

        #expect(origin.isDiffShown)
        #expect(!peer.isDiffShown)
        #expect(peer.effectiveDisplayMode == .source)
    }

    /// AC#1: 独立は差分に限らない。差分を選べないビルド・種別でも成立させたいので、
    /// 機能ゲートに依存しない `.source` でも同じことを別に固定する
    /// (`diffLoader` はゲート OFF で nil になるため、差分だけで測ると片側しか検証されない)。
    @Test("同一ファイルを 2 窓で開いても、ソース表示の選択は選んだ窓だけに効く")
    func doesNotMirrorSourceModeToOtherWindows() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DocumentStateIndependence.source", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .rendered)

        origin.setDisplayMode(.source)

        #expect(origin.effectiveDisplayMode == .source)
        #expect(peer.effectiveDisplayMode == .rendered)
    }

    /// AC#1 / AC#4: 生きている窓は、他窓が保存した倍率を拾わない。
    ///
    /// 保存ストアはアプリ全体で 1 つなので、他窓の操作はここへ現れる。これを提示中の窓が
    /// 読み直すと倍率が勝手に飛ぶ。`ViewerContentView` へ `ZoomStore` を渡す形に戻すか、
    /// 再ロード等の契機で `beginPresentingDocument` を呼ぶ形に戻すと、ここが落ちる。
    @Test("保存倍率が他窓に書き換えられても、開いている窓のライブ倍率は動かない")
    func keepsLiveZoomWhenStoredZoomChanges() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared], prefix: "DocumentStateIndependence.zoom", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: shared)
        let controller = try #require(fixture.manager.allControllers.first)
        #expect(controller.store.zoom == ZoomStore.defaultZoom)

        // 他窓が倍率を変えた状況(保存ストアはアプリ全体で 1 つ)。
        fixture.perFileState.zoom.setZoom(1.75, for: shared)

        #expect(controller.store.zoom == ZoomStore.defaultZoom)
    }

    /// AC#1 / AC#4: スクロール位置も同じ。保存値は「次に開くときの既定値」であって、
    /// 開いている窓の復元位置を後から書き換えるものではない。
    @Test("保存スクロール位置が他窓に書き換えられても、開いている窓の復元位置は動かない")
    func keepsLiveScrollPositionWhenStoredPositionChanges() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared], prefix: "DocumentStateIndependence.scroll", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: shared)
        let controller = try #require(fixture.manager.allControllers.first)
        let mode = ViewerBridge.ViewMode(isSourceMode: controller.store.isSourceMode)

        fixture.perFileState.scrollPosition.setScrollPosition(0.6, for: shared, mode: mode)

        #expect(controller.store.scrollPositionToRestore == 0)
    }

    /// AC#2: 窓を閉じて開き直すと、最後に設定した値(保存値)から始まる。ライブ値が窓の寿命で
    /// 消えることと、提示開始で保存値を読むことの両方が要る。片方でも欠けると落ちる。
    @Test("閉じてから開き直すと、保存された倍率とスクロール位置から始まる")
    func restoresStoredStateWhenReopening() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared], prefix: "DocumentStateIndependence.reopen", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        fixture.perFileState.zoom.setZoom(1.5, for: shared)
        fixture.perFileState.scrollPosition.setScrollPosition(0.4, for: shared, mode: .rendered)

        fixture.manager.openViewer(for: shared)
        let controller = try #require(fixture.manager.allControllers.first)

        #expect(controller.store.zoom == 1.5)
        #expect(controller.store.scrollPositionToRestore == 0.4)
    }

    /// cmd+U の戻り先の記憶は窓ごとのライブな状態で、同期しない(ADR 0002「状態の所在」)。
    /// 同期を戻すと、操作していない窓の cmd+U が「その窓では離れていないモード」へ戻る。
    @Test("cmd+U の戻り先の記憶は窓ごとで、操作していない窓は既定のソース表示へ戻る")
    func keepsSourceToggleReturnMemoryPerWindow() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DocumentStateIndependence.toggleReturn",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .source)
        origin.setDisplayMode(.diff)
        #expect(!peer.isDiffShown)

        // 操作した窓だけが cmd+U でレンダリング表示へ離れる。
        origin.toggleSourceView(nil)
        #expect(origin.effectiveDisplayMode == .rendered)
        #expect(peer.effectiveDisplayMode == .source)

        // 操作した窓の cmd+U は、離脱直前の実表示(差分)へ戻る。
        origin.toggleSourceView(nil)
        #expect(origin.isDiffShown)

        // もう片方は差分へ行っていないので、cmd+U はソース表示との往復にとどまる。
        peer.toggleSourceView(nil)
        #expect(peer.effectiveDisplayMode == .rendered)
        peer.toggleSourceView(nil)
        #expect(peer.effectiveDisplayMode == .source)
        #expect(!peer.isDiffShown)
    }
}
