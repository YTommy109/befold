@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// DirectoryLister.appendingOpenFile の回帰テスト。DirectoryListerTests から分離したのは、
/// swiftlint の type_body_length/file_length を超えないようにするため(TASK-298)。
@Suite
struct DirectoryListerAppendingOpenFileTests {
    @Test("appendingOpenFile は同じディレクトリの開いているファイルを末尾へ足す")
    func appendingOpenFileAppendsFileInSameDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let openFile = tmp.url.appendingPathComponent("notes.xyz")

        let result = DirectoryLister.appendingOpenFile(openFile, to: [], in: tmp.url)

        #expect(result.map(\.url.lastPathComponent) == ["notes.xyz"])
    }

    @Test("appendingOpenFile は生パスが一致すれば重複させない(シンボリックリンク解決なしの早期 return)")
    func appendingOpenFileSkipsDuplicateViaRawPath() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let openFile = tmp.url.appendingPathComponent("a.md")
        let listed = [FileListEntry(url: openFile, kind: .file)]

        let result = DirectoryLister.appendingOpenFile(openFile, to: listed, in: tmp.url)

        #expect(result.map(\.url.lastPathComponent) == ["a.md"])
    }

    /// 生パスの早期 return(TASK-298)を入れても、シンボリックリンク越しに同じディレクトリ・
    /// 同じファイルを指しているケースの正しさ(resolvingSymlinksInPath による判定)は
    /// 落としてはならない。生パスが食い違う場合にだけ正規化キーへフォールバックする。
    @Test("appendingOpenFile はシンボリックリンク越しに同じディレクトリを指していても追記する")
    func appendingOpenFileMatchesDirectoryThroughSymlink() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedDirectory()
        let openFile = link.appendingPathComponent("notes.xyz")

        let result = DirectoryLister.appendingOpenFile(openFile, to: [], in: real)

        #expect(result.map(\.url.lastPathComponent) == ["notes.xyz"])
    }

    /// 同様に、重複判定もシンボリックリンク越しの表記違いを見逃してはならない。
    /// resolvingSymlinksInPath は実在しないパスだとシンボリックリンクを解決しきらないため
    /// (このプロジェクトで既知の癖)、対象ファイルは実際に作成する。
    @Test("appendingOpenFile はシンボリックリンク越しの表記違いでも重複させない")
    func appendingOpenFileSkipsDuplicateThroughSymlink() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let (real, link) = try tmp.symlinkedDirectory()
        let existing = real.appendingPathComponent("a.md")
        try Data().write(to: existing)
        let openFile = link.appendingPathComponent("a.md")
        let listed = [FileListEntry(url: existing, kind: .file)]

        let result = DirectoryLister.appendingOpenFile(openFile, to: listed, in: real)

        #expect(result.map(\.url.lastPathComponent) == ["a.md"])
    }

    @Test("appendingOpenFile は別ディレクトリのファイルを追加しない")
    func appendingOpenFileIgnoresFileOutsideDirectory() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("sub"), withIntermediateDirectories: true
        )
        let openFile = tmp.url.appendingPathComponent("sub/notes.xyz")

        let result = DirectoryLister.appendingOpenFile(openFile, to: [], in: tmp.url)

        #expect(result.isEmpty)
    }
}
