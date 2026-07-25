@testable import BefoldKit
import Foundation
import Testing

private struct FakeGitIndex: GitFileIndexing {
    let files: [URL]?
    func trackedFiles(forFileAt url: URL) -> [URL]? {
        files
    }
}

private struct FakeFileReader: FileReading {
    let existing: Set<String>
    func fileExists(at url: URL) -> Bool {
        existing.contains(url.standardizedFileURL.path)
    }

    func isDirectory(at url: URL) -> Bool {
        false
    }

    func isExistingFile(at url: URL) -> Bool {
        existing.contains(url.standardizedFileURL.path)
    }

    func readString(from url: URL) throws -> String {
        ""
    }

    func readData(from url: URL) throws -> Data {
        Data()
    }

    func isBinary(at url: URL) -> Bool {
        false
    }

    func fileSize(at url: URL) -> Int? {
        nil
    }

    func modificationDate(at url: URL) -> Date? {
        nil
    }
}

struct TrackedPathResolverTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("相対で実在すればそのまま解決する(git を見ない)")
    func resolvesExistingRelative() {
        let base = url("/repo/docs/guide.md")
        let target = url("/repo/docs/img.png")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: [target.path]),
            gitIndex: FakeGitIndex(files: nil)
        )
        #expect(sut.resolve(href: "img.png", baseURL: base) == .resolved(target))
    }

    @Test("相対で実在しなければ git 追跡ファイルへサフィックス一致で解決する")
    func resolvesViaGitSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: [tracked])
        )
        #expect(sut.resolve(href: "utils.swift", baseURL: base) == .resolved(tracked))
    }

    @Test("git 管理外かつ相対で実在しなければ unresolved")
    func unresolvedWithoutGit() {
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: nil)
        )
        #expect(sut.resolve(href: "utils.swift", baseURL: url("/repo/x.md")) == .unresolved)
    }

    @Test("外部 URL は external、アンカー/空は ignored")
    func classifiesExternalAndIgnored() throws {
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: nil)
        )
        let base = url("/repo/x.md")
        #expect(try sut.resolve(href: "https://example.com", baseURL: base)
            == .external(#require(URL(string: "https://example.com"))))
        #expect(sut.resolve(href: "#section", baseURL: base) == .ignored)
    }

    @Test("行番号サフィックス付きでも解決できる")
    func resolvesWithLineSuffix() {
        let base = url("/repo/docs/guide.md")
        let tracked = url("/repo/src/utils.swift")
        let sut = TrackedPathResolver(
            fileReader: FakeFileReader(existing: []),
            gitIndex: FakeGitIndex(files: [tracked])
        )
        #expect(sut.resolve(href: "utils.swift:42", baseURL: base) == .resolved(tracked))
    }
}
