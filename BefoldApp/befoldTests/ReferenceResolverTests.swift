// BefoldApp/befoldTests/ReferenceResolverTests.swift
@testable import befold
import Foundation
import Testing

@Suite
struct ReferenceResolverTests {
    private let base = URL(fileURLWithPath: "/Users/test/docs/readme.md")

    @Test("https URL を external として解決する")
    func resolvesHttpsAsExternal() {
        let result = ReferenceResolver.resolve(
            href: "https://example.com", baseURL: base
        )
        guard case let .external(url) = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
        #expect(url.absoluteString == "https://example.com")
    }

    @Test("http URL を external として解決する")
    func resolvesHttpAsExternal() {
        let result = ReferenceResolver.resolve(
            href: "http://example.com/path", baseURL: base
        )
        guard case let .external(url) = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
        #expect(url.absoluteString == "http://example.com/path")
    }

    @Test("相対パスを baseURL の親ディレクトリ基準で解決する")
    func resolvesRelativePathAgainstBaseDirectory() {
        let result = ReferenceResolver.resolve(
            href: "./sub/file.swift", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/sub/file.swift")
    }

    @Test("親ディレクトリ参照を含む相対パスを正しく解決する")
    func resolvesParentDirectoryReference() {
        let result = ReferenceResolver.resolve(
            href: "../other/file.md", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/other/file.md")
    }

    @Test("行番号サフィックスを除去してパスを解決する")
    func stripsLineNumberSuffix() {
        let result = ReferenceResolver.resolve(
            href: "./file.swift:42", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/file.swift")
    }

    @Test("絶対パスをそのまま localFile として解決する")
    func resolvesAbsolutePath() {
        let result = ReferenceResolver.resolve(
            href: "/tmp/absolute.md", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/tmp/absolute.md")
    }

    @Test("mailto リンクを unsupported として返す")
    func mailtoIsUnsupported() {
        let result = ReferenceResolver.resolve(
            href: "mailto:user@example.com", baseURL: base
        )
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }

    @Test("空文字列を unsupported として返す")
    func emptyHrefIsUnsupported() {
        let result = ReferenceResolver.resolve(href: "", baseURL: base)
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }

    @Test("# で始まるアンカーリンクを unsupported として返す")
    func anchorLinkIsUnsupported() {
        let result = ReferenceResolver.resolve(
            href: "#section", baseURL: base
        )
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }
}
