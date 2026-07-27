@testable import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 実ファイルツリーを作って走査の上限と除外を検証する。
struct DirectoryFileScannerTests {
    private func relativePaths(_ result: DirectoryScanResult, from root: URL) -> [String] {
        result.files.map { PathRelativizer.relativePath(of: $0, relativeTo: root) }
    }

    @Test("直下と入れ子のファイルをすべて集める")
    func collectsNestedFiles() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.md", contents: "")
        _ = try tmp.file(atPath: "sub/b.md", contents: "")
        _ = try tmp.file(atPath: "sub/deeper/c.md", contents: "")

        let result = DirectoryFileScanner().scan(root: tmp.url, includingHiddenFiles: false)

        #expect(relativePaths(result, from: tmp.url) == ["a.md", "sub/b.md", "sub/deeper/c.md"])
        #expect(result.isTruncated == false)
    }

    @Test("拡張子で区別せず全ファイルを対象にする")
    func doesNotFilterByExtension() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "a.md", contents: "")
        _ = try tmp.file(named: "b.bin", contents: "")
        _ = try tmp.file(named: "noext", contents: "")

        let result = DirectoryFileScanner().scan(root: tmp.url, includingHiddenFiles: false)

        #expect(relativePaths(result, from: tmp.url) == ["a.md", "b.bin", "noext"])
    }

    @Test("除外ディレクトリの中身は集めない")
    func skipsExcludedDirectories() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "keep.md", contents: "")
        _ = try tmp.file(atPath: ".git/config", contents: "")
        _ = try tmp.file(atPath: "node_modules/pkg/index.js", contents: "")
        _ = try tmp.file(atPath: ".build/debug/x.o", contents: "")

        let result = DirectoryFileScanner().scan(root: tmp.url, includingHiddenFiles: true)

        #expect(relativePaths(result, from: tmp.url) == ["keep.md"])
    }

    @Test("隠しファイルは既定で除外し、指定時のみ含める")
    func honorsHiddenFilesSetting() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "visible.md", contents: "")
        _ = try tmp.file(named: ".hidden.md", contents: "")
        _ = try tmp.file(atPath: ".hiddendir/inside.md", contents: "")

        let hiddenExcluded = DirectoryFileScanner().scan(root: tmp.url, includingHiddenFiles: false)
        #expect(relativePaths(hiddenExcluded, from: tmp.url) == ["visible.md"])

        let hiddenIncluded = DirectoryFileScanner().scan(root: tmp.url, includingHiddenFiles: true)
        #expect(
            relativePaths(hiddenIncluded, from: tmp.url)
                == [".hidden.md", ".hiddendir/inside.md", "visible.md"]
        )
    }

    @Test("深さ上限を超えた階層は走査しない")
    func honorsDepthLimit() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(atPath: "one.md", contents: "")
        _ = try tmp.file(atPath: "a/two.md", contents: "")
        _ = try tmp.file(atPath: "a/b/three.md", contents: "")

        // depth 1 = ルート直下のみ
        let shallow = DirectoryFileScanner(maximumDepth: 1).scan(root: tmp.url, includingHiddenFiles: false)
        #expect(relativePaths(shallow, from: tmp.url) == ["one.md"])

        let twoLevels = DirectoryFileScanner(maximumDepth: 2).scan(root: tmp.url, includingHiddenFiles: false)
        #expect(relativePaths(twoLevels, from: tmp.url) == ["a/two.md", "one.md"])
    }

    @Test("件数上限に達したら打ち切りフラグを立てる")
    func honorsCountLimit() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        for index in 0 ..< 5 {
            _ = try tmp.file(named: "file\(index).md", contents: "")
        }

        let result = DirectoryFileScanner(maximumCount: 3).scan(root: tmp.url, includingHiddenFiles: false)

        #expect(result.files.count == 3)
        #expect(result.isTruncated)
    }

    @Test("上限に達しなければ打ち切りフラグは立たない")
    func noTruncationWithinLimits() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: "only.md", contents: "")

        let result = DirectoryFileScanner(maximumCount: 3).scan(root: tmp.url, includingHiddenFiles: false)

        #expect(result.isTruncated == false)
    }

    @Test("存在しないディレクトリは空を返す")
    func missingRootYieldsEmpty() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }

        let result = DirectoryFileScanner().scan(
            root: tmp.url.appendingPathComponent("nope"), includingHiddenFiles: false
        )

        #expect(result.files.isEmpty)
        #expect(result.isTruncated == false)
    }
}
