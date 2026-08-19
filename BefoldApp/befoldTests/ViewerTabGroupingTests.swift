import AppKit
@testable import befold
import BefoldKit
import Foundation
import Testing

/// タブグループ規則(ViewerTabGrouping)の単体検証。
/// 組み立て規則は NSWindow に依存しない純粋関数として切ってあるため、
/// 実ウィンドウを作らずに表で回せる。ウィンドウ生成を伴う経路の検証は
/// ViewerWindowManagerTabTests / SessionRestorerTests に残している。
@Suite
@MainActor
struct ViewerTabGroupingTests {
    @Test("可視なのにアクティブ Space に居ないウィンドウだけが救出対象と判定される")
    func isDetachedFromSpaceRequiresVisibleAndOffActiveSpace() {
        #expect(ViewerTabGrouping.isDetachedFromSpace(isVisible: true, isOnActiveSpace: false))
        #expect(!ViewerTabGrouping.isDetachedFromSpace(isVisible: true, isOnActiveSpace: true))
        #expect(!ViewerTabGrouping.isDetachedFromSpace(isVisible: false, isOnActiveSpace: false))
        #expect(!ViewerTabGrouping.isDetachedFromSpace(isVisible: false, isOnActiveSpace: true))
    }

    /// 結合先が無いときに落とさず独立ウィンドウのままにする縮退。
    /// これまで openViewer 経由でしか踏めず、規則そのものは固定されていなかった。
    @Test("結合先が nil ならタブ化せず独立ウィンドウのままにする")
    func attachAsTabKeepsWindowIndependentWithoutBaseWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        // 既定の isReleasedWhenClosed は true で、ARC 下の close() が過剰解放になる。
        window.isReleasedWhenClosed = false
        defer { window.close() }

        ViewerTabGrouping.attachAsTab(window, to: nil, select: true)

        #expect(window.tabGroup == nil)
    }

    /// ちらつき(TASK-529)の機序をそのまま測る。表示の瞬間にまだタブ結合されていなければ、
    /// AppKit が独立ウィンドウをタブへ畳む中間状態が 1 フレーム見える。
    @Test("タブとして開くウィンドウは表示の時点で既にタブグループに入っている")
    func presentJoinsTabGroupBeforeShowing() {
        let base = Self.makeWindow()
        let window = Self.makeWindow()
        defer {
            window.close()
            base.close()
        }
        base.orderFront(nil)

        var tabGroupAtShow: NSWindowTabGroup?
        var shown = false
        ViewerTabGrouping.present(window, asTabOf: base, select: true) {
            shown = true
            tabGroupAtShow = window.tabGroup
        }

        #expect(shown)
        #expect(tabGroupAtShow != nil)
        #expect(tabGroupAtShow === base.tabGroup)
    }

    /// window が無くても「タブにならなくとも開く」縮退が残っていること。
    @Test("window が nil でも表示だけは行われる")
    func presentWithoutWindowStillShows() {
        var shown = false
        ViewerTabGrouping.present(nil, asTabOf: nil, select: true) { shown = true }

        #expect(shown)
    }

    /// 既定の isReleasedWhenClosed は true で、ARC 下の close() が過剰解放になる。
    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test("ビューアパスを持つタブが1枚も無ければタブグループを作らない")
    func makeTabGroupReturnsNilWhenNoViewerTabs() {
        let group = ViewerTabGrouping.makeTabGroup(
            tabWindows: ["a", "b"], selectedWindow: "a", viewerPath: { _ in nil }
        )

        #expect(group == nil)
    }

    /// タブがすべてビューアの場合の入力と期待値。
    struct TabGroupCase: Sendable, CustomTestStringConvertible {
        let name: String
        let tabWindows: [String]
        let selectedWindow: String
        let expectedPaths: [String]
        let expectedSelectedPath: String
        var testDescription: String {
            name
        }
    }

    /// 単独ウィンドウは「全タブがビューア」の縮退ケースなので同じ表で回す。
    private nonisolated static let tabGroupCases: [TabGroupCase] = [
        TabGroupCase(
            name: "単独ウィンドウ",
            tabWindows: ["/a.mmd"], selectedWindow: "/a.mmd",
            expectedPaths: ["/a.mmd"], expectedSelectedPath: "/a.mmd"
        ),
        TabGroupCase(
            name: "先頭が選択されている3タブ",
            tabWindows: ["/a.mmd", "/b.mmd", "/c.mmd"], selectedWindow: "/a.mmd",
            expectedPaths: ["/a.mmd", "/b.mmd", "/c.mmd"], expectedSelectedPath: "/a.mmd"
        ),
        TabGroupCase(
            name: "中央が選択されている3タブ",
            tabWindows: ["/a.mmd", "/b.mmd", "/c.mmd"], selectedWindow: "/b.mmd",
            expectedPaths: ["/a.mmd", "/b.mmd", "/c.mmd"], expectedSelectedPath: "/b.mmd"
        ),
    ]

    @Test("タブ順は保たれ、選択タブのパスが selectedPath になる", arguments: tabGroupCases)
    func makeTabGroupKeepsTabOrderAndSelection(_ testCase: TabGroupCase) throws {
        let group = try #require(
            ViewerTabGrouping.makeTabGroup(
                tabWindows: testCase.tabWindows, selectedWindow: testCase.selectedWindow, viewerPath: { $0 }
            )
        )

        #expect(group.paths == testCase.expectedPaths)
        #expect(group.selectedPath == testCase.expectedSelectedPath)
    }

    @Test("ビューアでないタブは除外され、選択タブがビューアでなければ selectedPath は nil になる")
    func makeTabGroupSkipsNonViewerTabs() throws {
        let group = try #require(
            ViewerTabGrouping.makeTabGroup(
                tabWindows: ["/a.mmd", "other", "/c.mmd"], selectedWindow: "other",
                viewerPath: { $0.hasPrefix("/") ? $0 : nil }
            )
        )

        #expect(group.paths == ["/a.mmd", "/c.mmd"])
        #expect(group.selectedPath == nil)
    }
}
