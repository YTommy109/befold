import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Testing

/// URL 解決は実ファイルシステムを通し、文書の読み込みと監視は差し替える。
@Suite
@MainActor
struct DocumentTabOpeningIntegrationTests {
    @Test("複数文書を順序どおり開き、最初を選択する", testTimeLimit(), arguments: [false, true])
    func opensOrderedTabs(replacingBlank: Bool) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let files = try ["original.md", "first.md", "second.csv", "third.svg"].map {
            try tmp.file(named: $0, contents: "fixture")
        }
        let fixture = MockedViewerWindowManager(files: files)
        defer { fixture.closeAll() }
        let original = try #require(fixture.manager.openViewer(for: files[0])?.window)
        let blank = replacingBlank ? fixture.manager.blankTabs.open(relativeTo: original) : nil
        defer { blank?.close() }
        let source = blank?.window ?? original
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        await opener.openInTabs(Array(files.dropFirst()), relativeTo: source).value

        #expect(original.tabGroup?.windows.compactMap(ViewerTabGrouping.viewerPath) == files.map(\.normalizedPathKey))
        let selected = try #require(original.tabGroup?.selectedWindow)
        #expect(ViewerTabGrouping.viewerPath(of: selected) == files[1].normalizedPathKey)
        #expect(fixture.manager.allControllers.count == files.count)
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }

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

    @Test("対応拡張子を持つフォルダーを文書として開かない", testTimeLimit())
    func directoryDoesNotConsumeBlank() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let nested = try tmp.file(atPath: "folder.md/inside.md", contents: "fixture")
        let folder = nested.deletingLastPathComponent()
        let fixture = MockedViewerWindowManager(files: [nested], directories: [folder])
        defer { fixture.closeAll() }
        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        defer { blank.close() }
        let window = try #require(blank.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { nil })

        await opener.openInTabs([folder], relativeTo: window).value

        #expect(fixture.manager.allControllers.isEmpty)
        #expect(fixture.manager.blankTabs.controllers.count == 1)
    }

    @Test("UI の経路は手前の空タブを置き換える", testTimeLimit())
    func uiRouteReplacesActiveBlank() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let chosen = try tmp.file(named: "chosen.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, chosen])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        opener.openViewer(for: chosen)
        await waitForDeliveryOnMainActor { blank.isClosed }

        #expect(blank.isClosed)
        let replaced = try #require(fixture.manager.controllers[chosen.normalizedPathKey]?.first?.window)
        #expect(source.tabGroup?.windows == [source, replaced])
    }

    @Test("Finder と CLI の経路は空タブを置き換えない", testTimeLimit())
    func externalRouteKeepsBlank() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let chosen = try tmp.file(named: "chosen.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, chosen])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        opener.openSequentially([chosen])
        await waitForDeliveryOnMainActor { fixture.manager.controllers[chosen.normalizedPathKey] != nil }

        #expect(!blank.isClosed)
    }

    @Test("空タブのフォルダが ⌘O と Quick Open の起点になり、サイドバーが無ければ起点も無い")
    func blankTabAnchorsFollowSidebarFolder() throws {
        let origin = URL(fileURLWithPath: "/mock/folder/origin.md")
        let fixture = MockedViewerWindowManager(files: [origin])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let standalone = fixture.manager.blankTabs.open(relativeTo: nil)
        defer { standalone.close() }
        let folder = origin.deletingLastPathComponent().normalizedPathKey

        #expect(blank.sidebarDirectory?.normalizedPathKey == folder)
        #expect(blank.quickOpenAnchor?.deletingLastPathComponent().normalizedPathKey == folder)
        #expect(standalone.sidebarDirectory == nil)
        #expect(standalone.quickOpenAnchor == nil)
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

    /// Open Recent とブックマークは、手前のタブの種類に関わらず既存の窓を前面に出す(TASK-916)。
    /// Quick Open は手前のタブで開く規則なので、別の窓で開いていても空タブを置き換える。
    @Test("別の窓で開いているファイルは、記憶済みのリストからなら既存の窓を出し、Quick Open なら空タブを置き換える", testTimeLimit(), arguments: [true, false])
    func fileOpenElsewhereFollowsRoute(fromRecent: Bool) async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let elsewhere = try tmp.file(named: "elsewhere.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, elsewhere])
        defer { fixture.closeAll() }
        let other = try #require(fixture.manager.openViewer(for: elsewhere, disposition: .newWindow)?.window)
        let source = try #require(fixture.manager.openViewer(for: origin, disposition: .newWindow)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        let opening = fromRecent ? opener.openViewer(for: elsewhere) : opener.openInActiveTab(elsewhere)
        await opening.value

        let copies = fixture.manager.controllers[elsewhere.normalizedPathKey]?.count
        #expect(copies == (fromRecent ? 1 : 2))
        #expect(blank.isClosed == !fromRecent)
        withExtendedLifetime(other) {}
    }

    /// 1 回目が空タブを置き換えた後、2 回目は置き換えた文書を起点に読み替えられる。そのとき
    /// 既存の窓を出す判定が起点だけ外して要求を新しいタブのまま残すと、重複した窓が開く。
    @Test("空タブで同じ項目を続けて選んでも、重複した窓やタブが開かない", testTimeLimit())
    func repeatedRecentOpenDoesNotDuplicate() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let origin = try tmp.file(named: "origin.md", contents: "fixture")
        let chosen = try tmp.file(named: "chosen.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [origin, chosen])
        defer { fixture.closeAll() }
        let source = try #require(fixture.manager.openViewer(for: origin)?.window)
        let blank = fixture.manager.blankTabs.open(relativeTo: source)
        defer { blank.close() }
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil }, activeBlankTab: { blank })

        let first = opener.openViewer(for: chosen)
        let second = opener.openViewer(for: chosen)
        await first.value
        await second.value

        #expect(fixture.manager.controllers[chosen.normalizedPathKey]?.count == 1)
        #expect(source.tabGroup?.windows.count == 2)
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
}
