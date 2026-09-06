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

    @Test("スライドモードで開くと種別 .slide の新しいウィンドウになる")
    func opensAsASlideWindow() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )

        #expect(controller.kind == .slide)
    }

    @Test("スライド窓はツールバーを持たない")
    func hasNoToolbar() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )

        #expect(controller.toolbarController == nil)
        #expect(controller.window?.toolbar == nil)
    }

    /// 通常窓と対にして測る。片方だけだと「そもそもツールバーが付いていない」のか
    /// 「種別で外れている」のか区別できない。
    @Test("通常のビューア窓はツールバーを持つ")
    func viewerWindowStillHasToolbar() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(fixture.manager.openViewer(for: first))

        #expect(controller.toolbarController != nil)
        #expect(controller.window?.toolbar != nil)
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

    @Test("スライド窓のサイドバーは畳まれたまま開く")
    func opensWithTheSidebarCollapsed() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )

        #expect(controller.initialSidebarCollapsed)
        #expect(!controller.kind.allowsSidebar)
    }

    /// 折りたたみは種別の帰結であって利用者の選択ではないので、per-file の記憶へ
    /// 書いてはならない（ADR 0002）。書くと、そのファイルを次に通常窓で開いたときに
    /// サイドバーが畳まれた状態で開く。
    @Test("スライド窓は per-file のサイドバー開閉の記憶を書き換えない")
    func doesNotWriteThePerFileSidebarMemory() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) == nil)

        _ = try #require(fixture.manager.openViewer(for: first, disposition: .slide))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) == nil)
    }

    /// 対の確認。通常窓は従来どおり記憶へ書くので、上のテストが「そもそも誰も書かない」
    /// ことを測っているわけではないと分かる。
    @Test("通常のビューア窓は従来どおり per-file の記憶へ書く")
    func viewerWindowStillWritesThePerFileSidebarMemory() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        _ = try #require(fixture.manager.openViewer(for: first))

        #expect(fixture.perFileState.sidebar.isCollapsed(for: first) != nil)
    }

    @Test("スライド窓はセッションのスナップショットに入らない")
    func isExcludedFromTheSessionSnapshot() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let slide = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )
        let window = try #require(slide.window)

        #expect(ViewerTabGrouping.viewerPath(of: window) == nil)
        #expect(ViewerTabGrouping.tabGroup(of: window) == nil)
    }

    @Test("通常のビューア窓はセッションのスナップショットに入る")
    func viewerWindowIsIncludedInTheSessionSnapshot() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(fixture.manager.openViewer(for: first))
        let window = try #require(controller.window)

        #expect(ViewerTabGrouping.viewerPath(of: window) == first.normalizedPathKey)
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

    @Test("スライド窓は保存された寸法が無ければ 16:9 で開く")
    func opensAtSixteenByNineByDefault() throws {
        let fixture = makeFixture()
        defer { fixture.closeAll() }

        let controller = try #require(
            fixture.manager.openViewer(for: first, disposition: .slide)
        )
        let size = try #require(controller.window?.contentView?.frame.size)

        #expect(abs(size.width / size.height - 16.0 / 9.0) < 0.01, "実測 \(size)")
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
