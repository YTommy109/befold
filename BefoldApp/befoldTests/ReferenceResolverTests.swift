// BefoldApp/befoldTests/ReferenceResolverTests.swift
import BefoldKit
import Foundation
import Testing

@Suite
struct ReferenceResolverTests {
    private let base = URL(fileURLWithPath: "/Users/test/docs/readme.md")

    /// http/https スキーム(大文字小文字を含む)の URL は external として解決されること
    @Test(arguments: [
        (href: "https://example.com", expectedAbsoluteString: "https://example.com" as String?),
        (href: "http://example.com/path", expectedAbsoluteString: "http://example.com/path" as String?),
        // 大文字スキームでも external と判定されることのみ検証する(URL 正規化の詳細は問わない)
        (href: "HTTPS://EXAMPLE.COM/page", expectedAbsoluteString: nil as String?),
    ])
    func resolvesExternalURL(href: String, expectedAbsoluteString: String?) {
        let result = ReferenceResolver.resolve(href: href, baseURL: base)
        guard case let .external(url) = result else {
            Issue.record("expected .external, got \(result)")
            return
        }
        if let expectedAbsoluteString {
            #expect(url.absoluteString == expectedAbsoluteString)
        }
    }

    /// 相対パス・絶対パス・行番号/行列サフィックス・フラグメント・パーセントエンコードなど、
    /// あらゆる形式の href が baseURL 基準で正しいローカルパスに解決されること
    @Test(arguments: [
        // 相対パスを baseURL の親ディレクトリ基準で解決する
        (href: "./sub/file.swift", expectedPath: "/Users/test/docs/sub/file.swift"),
        // 親ディレクトリ参照を含む相対パスを正しく解決する
        (href: "../other/file.md", expectedPath: "/Users/test/other/file.md"),
        // 行番号サフィックスを除去してパスを解決する
        (href: "./file.swift:42", expectedPath: "/Users/test/docs/file.swift"),
        // 行:列サフィックスを除去してパスを解決する
        (href: "./ViewerStore.swift:12:5", expectedPath: "/Users/test/docs/ViewerStore.swift"),
        // 絶対パスをそのまま localFile として解決する
        (href: "/tmp/absolute.md", expectedPath: "/tmp/absolute.md"),
        // パーセントエンコードされた href をデコードして解決する
        (href: "%E8%A8%AD%E8%A8%88%E3%83%A1%E3%83%A2.md", expectedPath: "/Users/test/docs/設計メモ.md"),
        // #fragment を除去してパスを解決する
        (href: "./other.md#usage", expectedPath: "/Users/test/docs/other.md"),
        // スラッシュなし・行番号付きのファイル名をローカルパスとして解決する
        (href: "notes.md:12", expectedPath: "/Users/test/docs/notes.md"),
    ])
    func resolvesLocalFilePath(href: String, expectedPath: String) {
        let result = ReferenceResolver.resolve(href: href, baseURL: base)
        guard case let .localFile(url) = result else {
            Issue.record("expected .localFile, got \(result)")
            return
        }
        #expect(url.path == expectedPath)
    }

    /// mailto リンク・空文字列・アンカーリンクは unsupported として返されること
    @Test(arguments: ["mailto:user@example.com", "", "#section"])
    func resolvesUnsupportedHref(href: String) {
        let result = ReferenceResolver.resolve(href: href, baseURL: base)
        guard case .unsupported = result else {
            Issue.record("expected .unsupported, got \(result)")
            return
        }
    }
}
