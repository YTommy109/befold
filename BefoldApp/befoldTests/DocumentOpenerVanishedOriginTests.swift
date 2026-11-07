import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// 起点の窓が要求の後に消えたとき・置き換わったときの開き先(TASK-912 / 917 / 922)。
/// `DocumentTabOpeningIntegrationTests` から行数の上限のため分けた。URL 解決は実ファイルシステムを通す。
@Suite
@MainActor
struct DocumentOpenerVanishedOriginTests {
    @Test("解決中に閉じた空タブへの要求は、起点なしで開く", testTimeLimit())
    func closedDestinationOpensWithoutOrigin() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "file.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        let window = try #require(blank.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })
        let opening = opener.openInTabs([file], relativeTo: window)
        blank.close()

        await opening.value

        // 要求は捨てず、閉じた窓のタブにもしない(TASK-917)。
        let opened = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first?.window)
        #expect((opened.tabGroup?.windows.count ?? 1) == 1, "閉じた窓のタブとして開いた")
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }

    /// 先のドロップが空タブを閉じても、解決中だった後のドロップを捨てない。
    @Test("解決中の空タブへ続けてドロップしても後のファイルを失わない", testTimeLimit())
    func consecutiveDropsOnBlankKeepEveryFile() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let firstDrop = try tmp.file(named: "first.md", contents: "fixture")
        let secondDrop = try tmp.file(named: "second.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, firstDrop, secondDrop])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        // 本番と同じく、閉じたコントローラを誰も保持しない形で測る。窓だけを受け取る。
        let window = try #require(fixture.manager.blankTabs.open(relativeTo: source).window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        let first = opener.openInTabs([firstDrop], relativeTo: window)
        let second = opener.openInTabs([secondDrop], relativeTo: window)
        await first.value
        await second.value

        let paths = Set(source.tabGroup?.windows.compactMap(ViewerTabGrouping.viewerPath) ?? [])
        #expect(paths == Set([origin, firstDrop, secondDrop].map(\.normalizedPathKey)))
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }

    /// 起点が消えた要求の行き先は 1 箇所で決まる(TASK-917)。経路ごとに確かめる。
    @Test("解決中に空タブを閉じても、記憶済みのリストと Quick Open で選んだファイルが開く", testTimeLimit(), arguments: [true, false])
    func closedBlankStillOpensChosenFile(fromRecent: Bool) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let chosen = try tmp.file(named: "chosen.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, chosen])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        let blankWindow = try #require(blank.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        let opening = fromRecent ? opener.openViewer(for: chosen) : opener.openInActiveTab(chosen)
        blank.close()
        await opening.value

        let opened = try #require(fixture.manager.controllers[chosen.normalizedPathKey]?.first?.window)
        #expect(source.tabGroup?.windows.contains(opened) != true, "閉じた空タブの窓のタブとして開いた")
        withExtendedLifetime(blankWindow) {}
    }

    @Test("空タブで続けて選んだ文書は、最後に選んだものが手前に出る", testTimeLimit())
    func lastChosenDocumentIsSelected() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let firstChoice = try tmp.file(named: "first.md", contents: "fixture")
        let lastChoice = try tmp.file(named: "last.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, firstChoice, lastChoice])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        let first = opener.openViewer(for: firstChoice)
        let last = opener.openViewer(for: lastChoice)
        await first.value
        await last.value

        let lastWindow = try #require(fixture.manager.controllers[lastChoice.normalizedPathKey]?.first?.window)
        #expect(source.tabGroup?.selectedWindow === lastWindow)
    }

    @Test("閉じた空タブのサイドバーから届いた選択は、閉じた窓のタブを作らない")
    func closedBlankSidebarSelectionDoesNotJoinClosedWindow() throws {
        let origin = URL(fileURLWithPath: "/mock/folder/origin.md")
        let chosen = URL(fileURLWithPath: "/mock/folder/chosen.md")
        let fixture = MockedViewerWindowManager(files: [origin, chosen])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        let blankWindow = try #require(blank.window)
        blank.close()

        _ = blank.performFileSwitch(to: chosen)

        let opened = try #require(fixture.manager.controllers[chosen.normalizedPathKey]?.first?.window)
        #expect(source.tabGroup?.windows.contains(opened) != true, "閉じた空タブの窓のタブとして開いた")
        withExtendedLifetime(blankWindow) {}
    }

    /// 読み替えたタブは置き換えた文書の直後に置く。末尾へ置くと、文書の説明と食い違う。
    @Test("置き換え先へ読み替えたタブは、置き換えた文書の直後に開く", testTimeLimit())
    func redirectedTabOpensRightAfterReplacement() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let trailing = try tmp.file(named: "trailing.md", contents: "fixture")
        let firstChoice = try tmp.file(named: "first.md", contents: "fixture")
        let lastChoice = try tmp.file(named: "last.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, trailing, firstChoice, lastChoice])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let blankWindow = try #require(blank.window)
        let trailingWindow = try #require(fixture.manager.openViewer(
            for: trailing, disposition: .newTab, relativeTo: blankWindow
        )?.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        let first = opener.openViewer(for: firstChoice)
        let last = opener.openViewer(for: lastChoice)
        await first.value
        await last.value

        let firstWindow = try #require(fixture.manager.controllers[firstChoice.normalizedPathKey]?.first?.window)
        let lastWindow = try #require(fixture.manager.controllers[lastChoice.normalizedPathKey]?.first?.window)
        #expect(source.tabGroup?.windows == [source, firstWindow, lastWindow, trailingWindow])
    }

    /// パネルの表示中に空タブを閉じ、最初のファイルが別の窓で開いていたとき、残りをその窓へ入れない。
    @Test("起点の空タブが閉じた一括オープンは、最初の文書が入った既存の窓を残りの起点にしない", testTimeLimit())
    func closedBlankBatchDoesNotJoinUnrelatedWindow() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let elsewhere = try tmp.file(named: "elsewhere.md", contents: "fixture")
        let rest = try tmp.file(named: "rest.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, elsewhere, rest])
        defer { fixture.closeAll() }
        let other = try #require(fixture.manager.openViewer(for: elsewhere, disposition: .newWindow)?.window)
        let source = try #require(fixture.manager.openViewer(for: origin, disposition: .newWindow)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        let blankWindow = try #require(blank.window)
        blank.close()
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        await opener.openInTabs([elsewhere, rest], relativeTo: blankWindow).value

        let restWindow = try #require(fixture.manager.controllers[rest.normalizedPathKey]?.first?.window)
        #expect(fixture.manager.controllers[elsewhere.normalizedPathKey]?.count == 1)
        #expect(other.tabGroup?.windows.contains(restWindow) != true, "無関係な既存の窓のタブとして開いた")
        #expect(source.tabGroup?.windows.contains(restWindow) != true, "閉じた空タブの窓のタブとして開いた")
    }

    /// 最初の文書が新しく開いた窓へは、残りをまとめる。起点が閉じていても散らばらない。
    @Test("起点の窓が閉じていても、一括の残りは最初の文書が新しく開いた窓へまとまる", testTimeLimit())
    func closedSourceBatchGathersIntoFirstNewWindow() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let firstDrop = try tmp.file(named: "first.md", contents: "fixture")
        let secondDrop = try tmp.file(named: "second.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, firstDrop, secondDrop])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })
        source.close()

        await opener.openInTabs([firstDrop, secondDrop], relativeTo: source).value

        let firstWindow = try #require(fixture.manager.controllers[firstDrop.normalizedPathKey]?.first?.window)
        let secondWindow = try #require(fixture.manager.controllers[secondDrop.normalizedPathKey]?.first?.window)
        #expect(firstWindow.tabGroup?.windows.contains(secondWindow) == true)
    }
}
