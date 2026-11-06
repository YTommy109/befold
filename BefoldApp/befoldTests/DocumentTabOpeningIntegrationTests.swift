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
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil })

        await opener.openInTabs(Array(files.dropFirst()), relativeTo: source).value

        #expect(original.tabGroup?.windows.compactMap(ViewerTabGrouping.viewerPath) == files.map(\.normalizedPathKey))
        let selected = try #require(original.tabGroup?.selectedWindow)
        #expect(ViewerTabGrouping.viewerPath(of: selected) == files[1].normalizedPathKey)
        #expect(fixture.manager.allControllers.count == files.count)
        #expect(fixture.manager.blankTabs.controllers.isEmpty)
    }

    @Test("解決中に閉じた空タブを復活させない", testTimeLimit())
    func closedDestinationDoesNotReopen() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "file.md", contents: "fixture")
        let fixture = MockedViewerWindowManager(files: [file])
        defer { fixture.closeAll() }
        let blank = fixture.manager.blankTabs.open(relativeTo: nil)
        let window = try #require(blank.window)
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil })
        let opening = opener.openInTabs([file], relativeTo: window)
        blank.close()

        await opening.value

        #expect(fixture.manager.allControllers.isEmpty)
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
        let opener = DocumentOpener(windowManager: fixture.manager, activeViewer: { nil })

        await opener.openInTabs([folder], relativeTo: window).value

        #expect(fixture.manager.allControllers.isEmpty)
        #expect(fixture.manager.blankTabs.controllers.count == 1)
    }
}
