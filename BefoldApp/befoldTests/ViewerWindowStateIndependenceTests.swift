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
    /// 読み直すと倍率が勝手に飛ぶ。再ロード等の契機で `beginPresentingDocument` を
    /// 呼ぶ形に戻すと、ここが落ちる。
    ///
    /// `ViewerContentView` へ `ZoomStore` を渡す形へ戻す回帰はここでは検知できない
    /// (`store.zoom` は 1.25 のまま、描画へ渡る値だけがずれる)。そちらは
    /// `ViewerContentViewStoreIsolationTests` が担保する。
    @Test("保存倍率が他窓に書き換えられても、開いている窓のライブ倍率は動かない")
    func keepsLiveZoomWhenStoredZoomChanges() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared], prefix: "DocumentStateIndependence.zoom", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        // 提示開始で読む値と、その後に他窓が書く値を別にしておく。既定値のまま開くと
        // 「読んでいない」と「読み直していない」を区別できない(このテストが空振りになる)。
        fixture.perFileState.zoom.setZoom(1.25, for: shared)
        fixture.manager.openViewer(for: shared)
        let controller = try #require(fixture.manager.allControllers.first)
        #expect(controller.store.zoom == 1.25)

        // 他窓が倍率を変えた状況(保存ストアはアプリ全体で 1 つ)。
        fixture.perFileState.zoom.setZoom(1.75, for: shared)

        #expect(controller.store.zoom == 1.25)
    }

    /// AC#1 / AC#4: スクロール位置は永続化せず、窓ごとの記憶で持つ(TASK-565)。
    /// 片方の窓でスクロールしても、同じファイルを開いているもう片方の復元位置は動かない。
    @Test("同じファイルの 2 窓は、互いのスクロール位置を持たない")
    func keepsScrollPositionPerWindow() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DocumentStateIndependence.scroll", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        let (origin, peer) = try openTwoWindowsOnSharedFile(fixture, mode: .rendered)
        let mode = ViewerBridge.ViewMode(isSourceMode: origin.store.isSourceMode)

        origin.documentPresenter.recordScrollPosition(0.6, for: shared, mode: mode)

        #expect(origin.documentPresenter.presentationMemory.scrollPosition(for: shared, mode: mode) == 0.6)
        #expect(peer.documentPresenter.presentationMemory.scrollPosition(for: shared, mode: mode) == 0)
        #expect(peer.store.scrollPositionToRestore == 0)
    }

    /// AC#2: 窓を閉じて開き直すと、倍率は保存値から始まる。ライブ値が窓の寿命で
    /// 消えることと、提示開始で保存値を読むことの両方が要る。片方でも欠けると落ちる。
    ///
    /// スクロール位置と表示モードは**永続化しない**ので、開き直すと初期状態へ戻る
    /// (TASK-565)。ここが「保存値から始まる」に戻ったら、永続化が復活している。
    ///
    /// 1 窓目のライブ倍率・位置を保存値と**別の値**へ動かしてから閉じる。倍率の永続化は
    /// レンダラからの通知経路(`viewerDidChangeZoom`)でしか起きないため、ここでの直接代入は
    /// 保存値を書き換えない。したがって再オープン後に 2.0 / 0.9 が出たら、それは閉じた窓の
    /// ライブ値が(コントローラや store の使い回し等で)漏れているということになる。
    @Test("閉じてから開き直すと、倍率は保存値から・位置と表示モードは初期状態から始まる")
    func restoresStoredZoomButNotVolatileStateWhenReopening() throws {
        let fixture = MockedViewerWindowManager(
            files: [shared], prefix: "DocumentStateIndependence.reopen", contents: "let a = 1"
        )
        defer { fixture.closeAll() }
        fixture.perFileState.zoom.setZoom(1.5, for: shared)

        fixture.manager.openViewer(for: shared)
        let first = try #require(fixture.manager.allControllers.first)
        #expect(first.store.zoom == 1.5)
        #expect(first.store.scrollPositionToRestore == 0)
        first.documentPresenter.recordScrollPosition(0.4, for: shared, mode: .rendered)
        first.setDisplayMode(.source)

        first.store.zoom = 2.0
        first.store.scrollPositionToRestore = 0.9
        first.close()
        #expect(fixture.manager.allControllers.isEmpty)

        fixture.manager.openViewer(for: shared)
        let reopened = try #require(fixture.manager.allControllers.first)
        #expect(reopened !== first)
        #expect(reopened.store.zoom == 1.5)
        #expect(reopened.store.scrollPositionToRestore == 0)
        #expect(reopened.documentPresenter.presentationMemory.displayMode(for: shared) == .rendered)
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
