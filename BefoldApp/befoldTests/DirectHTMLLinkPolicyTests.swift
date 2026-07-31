import AppKit
@testable import befold
import BefoldRenderKit
import Testing

@Suite("Direct HTML link policy")
struct DirectHTMLLinkPolicyTests {
    private let currentURL = URL(fileURLWithPath: "/tmp/test/index.html")

    private func fileURL(_ path: String, fragment: String) throws -> URL {
        var components = try #require(
            URLComponents(url: URL(fileURLWithPath: path), resolvingAgainstBaseURL: false)
        )
        components.fragment = fragment
        return try #require(components.url)
    }

    @Test("同一文書内フラグメントは allowNativeNavigation を返す")
    func sameDocumentFragment() throws {
        let url = try fileURL("/tmp/test/index.html", fragment: "section1")
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: []
        )
        #expect(result == .allowNativeNavigation)
    }

    @Test("cmd 付きフラグメントも allowNativeNavigation を返す")
    func sameDocumentFragmentWithCmd() throws {
        let url = try fileURL("/tmp/test/index.html", fragment: "section1")
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: .command
        )
        #expect(result == .allowNativeNavigation)
    }

    @Test("ローカルファイル cmd 無しは openLocalFile currentTab を返す")
    func localFileSameWindow() {
        let url = URL(fileURLWithPath: "/tmp/test/other.md")
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: []
        )
        #expect(result == .openLocalFile(url: url, disposition: .currentTab))
    }

    @Test("ローカルファイル cmd ありは openLocalFile newTab を返す")
    func localFileNewWindow() {
        let url = URL(fileURLWithPath: "/tmp/test/other.md")
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: .command
        )
        #expect(result == .openLocalFile(url: url, disposition: .newTab))
    }

    @Test("http URL は openExternal を返す")
    func httpExternal() throws {
        let url = try #require(URL(string: "https://example.com"))
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: []
        )
        #expect(result == .openExternal(url: url))
    }

    @Test("http URL cmd ありでも openExternal を返す")
    func httpExternalWithCmd() throws {
        let url = try #require(URL(string: "https://example.com"))
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: .command
        )
        #expect(result == .openExternal(url: url))
    }

    @Test("mailto は ignore を返す")
    func mailtoIgnored() throws {
        let url = try #require(URL(string: "mailto:test@example.com"))
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: []
        )
        #expect(result == .ignore)
    }

    @Test("ローカルファイルのフラグメント付きはフラグメントを除去して openLocalFile を返す")
    func localFileWithFragment() throws {
        let url = try fileURL("/tmp/test/other.md", fragment: "heading")
        let result = ViewerRenderer.directHTMLLinkPolicy(
            url: url, currentURL: currentURL, modifierFlags: []
        )
        let expected = URL(fileURLWithPath: "/tmp/test/other.md")
        #expect(result == .openLocalFile(url: expected, disposition: .currentTab))
    }

    @Test("直接 HTML モードでも cmd+クリックは別タブ、cmd+shift+クリックは新規ウィンドウになる")
    func directHTMLLinkUsesSharedDispositionTable() {
        let target = URL(fileURLWithPath: "/repo/docs/a.html")

        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [.command])
                == .openLocalFile(url: target, disposition: .newTab)
        )
        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [.command, .shift])
                == .openLocalFile(url: target, disposition: .newWindow)
        )
        #expect(
            ViewerRenderer.directHTMLLinkPolicy(url: target, currentURL: nil, modifierFlags: [])
                == .openLocalFile(url: target, disposition: .currentTab)
        )
    }
}
