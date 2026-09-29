import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// スライド窓を実際に開いて、器の性質を実ウィンドウで確かめる(TASK-593.2 / 593.3)。
///
/// `MockedViewerWindowManager` は実 `NSWindow` を作る（store と directoryLister だけ
/// モック済み）ので、「ツールバーが無い」「タブに合流しない」「per-file の記憶を汚さない」
/// といった、純粋関数のテストでは届かない性質をここで測れる。
@Suite
@MainActor
struct SlideWindowIntegrationTests {
    private let first = URL(fileURLWithPath: "/mock/first.md")
    private let second = URL(fileURLWithPath: "/mock/second.md")

    private func makeFixture() -> MockedViewerWindowManager {
        MockedViewerWindowManager(
            files: [first, second], prefix: "SlideWindowIntegrationTests"
        )
    }

    /// 「slide で 1 回開く」だけで決まる性質をまとめて測る（窓を 1 枚だけ作る）。
    /// どれか 1 つが崩れても、その #expect が個別に落ちる。
    @Test("スライド窓は種別 .slide で、ツールバー・サイドバー・per-file の記憶・セッションの記録を持たない")
    func slideWindowProperties() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }
        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) == nil)

        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )
        let window = try #require(controller.window)

        #expect(controller.kind == .slide)
        #expect(controller.toolbarController == nil)
        #expect(window.toolbar == nil)
        // 種別そのものの allowsSidebar は ViewerWindowKindTests が窓なしで測る。
        #expect(controller.initialSidebarCollapsed)
        // 折りたたみは種別の帰結であって利用者の選択ではないので、per-file の記憶へ
        // 書いてはならない（ADR 0002）。書くと、そのファイルを次に通常窓で開いたときに
        // サイドバーが畳まれた状態で開く。
        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) == nil)
        #expect(ViewerTabGrouping.viewerPath(of: window) == nil)
        #expect(ViewerTabGrouping.tabGroup(of: window) == nil)
    }

    /// 上のテストと対にして測る。片方だけだと「そもそもツールバーが付いていない」
    /// 「そもそも誰も記憶へ書かない」のか、「種別で外れている」のか区別できない。
    @Test("通常のビューア窓はツールバーを持ち、per-file の記憶へ書き、セッションの記録に入る")
    func viewerWindowCounterparts() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(fixture.manager.openViewer(for: first))
        let window = try #require(controller.window)

        #expect(controller.toolbarController != nil)
        #expect(window.toolbar != nil)
        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) != nil)
        #expect(ViewerTabGrouping.viewerPath(of: window) == first.normalizedPathKey)
    }

    @Test("スライド窓はタブ結合を禁止していて、起点のタブグループに入らない")
    func neverJoinsATabGroup() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        fixture.manager.openViewer(for: first)
        let sourceWindow = fixture.manager.window(forPath: first.normalizedPathKey)
        let slide = try #require(
            fixture.manager.openViewer(for: second, disposition: .slide, relativeTo: sourceWindow)
        )

        #expect(slide.window?.tabbingMode == .disallowed)
        #expect(slide.window?.tabGroup?.windows.contains { $0 === sourceWindow } != true)
    }

    /// 前後移動キーが実際にファイルを切り替えるところまでを、キーイベントを作らずに測る
    /// （キー → 動作の対応は `SlideKeyActionTests`、隣の解決は
    /// `FileListSnapshotFileNeighbourTests` が測る。ここはその 2 つと窓の配線が
    /// つながっていることの担保 / TASK-593.3）。
    @Test("スライド窓の前後移動が表示中のファイルを実際に切り替える")
    func adjacentFileNavigationSwitchesTheDocument() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }
        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )
        let directory = first.deletingLastPathComponent()
        controller.fileListModel.setEntries(
            [FileListEntry(url: first, kind: .file), FileListEntry(url: second, kind: .file)],
            for: directory, didFailEnumeration: false
        )
        controller.fileListModel.selection = first

        controller.moveToAdjacentFile(.next)

        #expect(controller.fileURL.normalizedPathKey == second.normalizedPathKey)

        controller.moveToAdjacentFile(.previous)

        #expect(controller.fileURL.normalizedPathKey == first.normalizedPathKey)
    }

    @Test("端では前後移動が何もしない（周回しない）")
    func adjacentFileNavigationStopsAtTheEdges() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }
        let controller = try #require(
            fixture.manager.openViewer(for: second, disposition: .slide)
        )
        let directory = first.deletingLastPathComponent()
        controller.fileListModel.setEntries(
            [FileListEntry(url: first, kind: .file), FileListEntry(url: second, kind: .file)],
            for: directory, didFailEnumeration: false
        )
        controller.fileListModel.selection = second

        controller.moveToAdjacentFile(.next)

        #expect(controller.fileURL.normalizedPathKey == second.normalizedPathKey)
    }

    /// 種別で寸法の壺が分かれていることを、窓を実際にリサイズして測る(TASK-593.5)。
    /// 分かれていないと、プレゼン用に広げた寸法が次に開く通常窓へそのまま漏れる。
    @Test("スライド窓をリサイズしても通常窓の既定寸法は変わらない")
    func resizingASlideWindowDoesNotChangeTheViewerDefault() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }
        fixture.windowFrame.recordUserAdjustedFrame("0 0 900 700 0 0 1920 1080", for: .viewer)
        let slide = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )
        let window = try #require(slide.window)

        window.setFrame(NSRect(x: 0, y: 0, width: 1600, height: 900), display: false)
        // ライブリサイズの確定と同じ契機を直接叩く（実 UI のドラッグは再現できない）。
        slide.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        #expect(
            fixture.windowFrame.lastUserAdjustedFrameDescriptor(for: .viewer)
                == "0 0 900 700 0 0 1920 1080"
        )
        #expect(fixture.windowFrame.lastUserAdjustedFrameDescriptor(for: .slide) != nil)
    }

    @Test("スライドモードは既に開いているファイルでも必ず新しい窓を開く")
    func alwaysOpensANewWindow() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let existing = try #require(fixture.manager.openViewer(for: first))
        let slide = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )

        #expect(slide !== existing)
        #expect(slide.kind == .slide)
    }
}
