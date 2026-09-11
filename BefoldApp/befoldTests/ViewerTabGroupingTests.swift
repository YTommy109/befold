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

        ViewerTabGrouping.attachAsTab(window, to: nil, placement: .end, select: true)

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
        ViewerTabGrouping.present(window, asTabOf: base, placement: .afterSource, select: true) {
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
        ViewerTabGrouping.present(nil, asTabOf: nil, placement: .end, select: true) { shown = true }

        #expect(shown)
    }

    /// Window メニューに載せるのは各グループの選択タブだけ、という判定(TASK-531)。
    /// タブ化されていないウィンドウ(selectedTabOfGroup == nil)は隠さない。
    @Test("選択タブ以外だけが Window メニューから外れると判定される")
    func isExcludedFromWindowsMenuHidesOnlyBackgroundTabs() {
        let selected = NSObject()
        let background = NSObject()

        #expect(!ViewerTabGrouping.isExcludedFromWindowsMenu(selected, selectedTabOfGroup: selected))
        #expect(ViewerTabGrouping.isExcludedFromWindowsMenu(background, selectedTabOfGroup: selected))
        #expect(!ViewerTabGrouping.isExcludedFromWindowsMenu(background, selectedTabOfGroup: nil))
    }

    /// 実ウィンドウのタブグループに対して、選択タブだけが Window メニューへ残ること。
    /// 選択を切り替えたら追随して入れ替わることまで見る(片方向だけ直すと、
    /// 一度外れたタブが選択されてもメニューへ戻らない)。
    @Test("タブグループでは選択中のタブだけが Window メニューに残る")
    func syncWindowsMenuMembershipKeepsOnlySelectedTab() {
        let base = Self.makeWindow()
        let tab = Self.makeWindow()
        let standalone = Self.makeWindow()
        defer {
            tab.close()
            base.close()
            standalone.close()
        }
        base.orderFront(nil)
        ViewerTabGrouping.attachAsTab(tab, to: base, placement: .end, select: true)
        #expect(base.tabGroup != nil)

        ViewerTabGrouping.syncWindowsMenuMembership(among: [base, tab, standalone])

        #expect(base.isExcludedFromWindowsMenu)
        #expect(!tab.isExcludedFromWindowsMenu)
        #expect(!standalone.isExcludedFromWindowsMenu)

        ViewerTabGrouping.selectTab(base)
        ViewerTabGrouping.syncWindowsMenuMembership(among: [base, tab, standalone])

        #expect(!base.isExcludedFromWindowsMenu)
        #expect(tab.isExcludedFromWindowsMenu)
    }

    /// `addTabbedWindow(_:ordered: .above)` が「anchor の直後」に入ることの**実測**(TASK-611)。
    /// Apple のドキュメント本文には位置の明記が無いため、実ウィンドウ 3 枚のグループへ
    /// 4 枚目を 1 枚目基準で結合し、`tabGroup.windows` の並びで確かめる。
    /// ここが落ちたら `.afterSource` の実装(anchor = baseWindow)を見直すこと。
    @Test("afterSource は起点タブの直後に入る")
    func attachAsTabAfterSourceInsertsRightAfterBase() {
        let windows = (0 ..< 4).map { _ in Self.makeWindow() }
        let (first, second, third, fourth) = (windows[0], windows[1], windows[2], windows[3])
        defer { windows.reversed().forEach { $0.close() } }
        first.orderFront(nil)
        ViewerTabGrouping.attachAsTab(second, to: first, placement: .end, select: false)
        ViewerTabGrouping.attachAsTab(third, to: first, placement: .end, select: false)
        #expect(Self.tabOrder(of: first) == Self.ids([first, second, third]))

        ViewerTabGrouping.attachAsTab(fourth, to: first, placement: .afterSource, select: false)

        #expect(Self.tabOrder(of: first) == Self.ids([first, fourth, second, third]))
    }

    /// 起点がグループの先頭でも、`.end` なら末尾へ入る(TASK-611)。
    @Test("end は起点の位置に関係なくタブバーの末尾に入る")
    func attachAsTabEndAppendsRegardlessOfBase() {
        let windows = (0 ..< 3).map { _ in Self.makeWindow() }
        let (first, second, third) = (windows[0], windows[1], windows[2])
        defer { windows.reversed().forEach { $0.close() } }
        first.orderFront(nil)
        ViewerTabGrouping.attachAsTab(second, to: first, placement: .end, select: false)

        ViewerTabGrouping.attachAsTab(third, to: first, placement: .end, select: false)

        #expect(Self.tabOrder(of: first) == Self.ids([first, second, third]))
    }

    private static func tabOrder(of window: NSWindow) -> [ObjectIdentifier]? {
        window.tabGroup?.windows.map(ObjectIdentifier.init)
    }

    private static func ids(_ windows: [NSWindow]) -> [ObjectIdentifier] {
        windows.map(ObjectIdentifier.init)
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
