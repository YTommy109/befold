@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// フォルダー行の `containsSupportedFile`(「開ける対応ファイルを 1 件取れるか」)の
/// 回帰テスト。DirectoryListerTests から分離したのは、swiftlint の
/// type_body_length/file_length を超えないようにするため(TASK-298 と同じ理由)。
@Suite
struct DirectoryListerSupportedFileTests {
    @Test("listEntries はフォルダーエントリに対応形式ファイルの有無を事前計算する")
    func listEntriesPrecomputesContainsSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("withSupported"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "withSupported/diagram.mmd", contents: "graph TD;")
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent("withoutSupported"),
            withIntermediateDirectories: true
        )
        _ = try tmp.file(named: "withoutSupported/unknown.xyz", contents: "not supported")

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()
        let folders = entries.filter { $0.kind == .folder }

        let withSupported = folders.first { $0.url.lastPathComponent == "withSupported" }
        let withoutSupported = folders.first { $0.url.lastPathComponent == "withoutSupported" }
        #expect(withSupported?.containsSupportedFile == true)
        #expect(withoutSupported?.containsSupportedFile == false)
    }

    /// 読めないフォルダは「開けるファイルが無いフォルダ」と同じ `false` になる。
    ///
    /// これは畳み忘れではなく決めた振る舞い。`containsSupportedFile` の唯一の消費側は
    /// コンテキストメニュー「新しいタブ/ウィンドウで開く」の `disabled` 判定であり、
    /// 問うているのは「開ける対応ファイルを 1 件取れるか」だけ。読めないフォルダで
    /// 有効化しても、押した先の `firstSupportedFile` が nil を返して何も起きない
    /// ボタンになる。列挙失敗そのものの区別は、ツリー展開側の
    /// `SidebarDisclosureState.expandedFailed`(TASK-404)が担う。
    ///
    /// root 実行では chmod 000 でも読めてしまい逆の枝を通るためスキップする。
    @Test("読めないフォルダも containsSupportedFile は false", .enabled(if: getuid() != 0))
    func listEntriesTreatsUnreadableFolderAsNotContainingSupportedFile() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let locked = tmp.url.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        _ = try tmp.file(named: "locked/diagram.mmd", contents: "graph TD;")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path
            )
        }

        let entries = DirectoryLister.listing(in: tmp.url, sortOrder: .foldersFirst).rows()
        let lockedEntry = entries.first { $0.url.lastPathComponent == "locked" }

        // 中に .mmd があっても、読めない以上「取れない」= false。
        #expect(lockedEntry?.kind == .folder)
        #expect(lockedEntry?.containsSupportedFile == false)
        // 一方、列挙失敗そのものは子リスト側で nil として区別されたまま残る。
        #expect(
            DirectoryLister.childEntries(
                in: locked, sortOrder: .foldersFirst, showHiddenFiles: false
            ) == nil
        )
    }
}
