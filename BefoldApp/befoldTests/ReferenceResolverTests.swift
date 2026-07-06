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

    @Test("大文字スキームの HTTPS URL を external として解決する")
    func resolvesUppercaseSchemeAsExternal() {
        let result = ReferenceResolver.resolve(
            href: "HTTPS://EXAMPLE.COM/page", baseURL: base
        )
        guard case .external = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
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

    @Test("行:列サフィックスを除去してパスを解決する")
    func stripsLineColumnSuffix() {
        let result = ReferenceResolver.resolve(
            href: "./ViewerStore.swift:12:5", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/ViewerStore.swift")
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

    @Test("パーセントエンコードされた href をデコードして解決する")
    func resolvesPercentEncodedHref() {
        let result = ReferenceResolver.resolve(
            href: "%E8%A8%AD%E8%A8%88%E3%83%A1%E3%83%A2.md", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/設計メモ.md")
    }

    @Test("#fragment を除去してパスを解決する")
    func stripsFragment() {
        let result = ReferenceResolver.resolve(
            href: "./other.md#usage", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/other.md")
    }

    @Test("スラッシュなし・行番号付きのファイル名をローカルパスとして解決する")
    func resolvesBareFilenameWithLineNumber() {
        let result = ReferenceResolver.resolve(
            href: "notes.md:12", baseURL: base
        )
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == "/Users/test/docs/notes.md")
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
