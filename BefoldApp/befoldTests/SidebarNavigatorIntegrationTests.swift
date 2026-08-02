import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// SidebarNavigator のうち、実ディレクトリ構造(symlink 解決)が本質のテスト。
/// symlink 祖先経由の別表記パスでも同一ディレクトリと判定されるかは `standardizedFileURL`
/// (symlink 解決なし)と `normalizedPathKey`(symlink 解決あり)の混在で /tmp ↔ /private/tmp の
/// ようなケースが割れる問題の回帰テスト。世代ガード競合・フィルタ持続など、実列挙結果そのものが
/// 本質でない選択ポリシー検証は SidebarNavigatorGenerationTests(unit)へ、rootDirectory の追従・
/// フォルダー選択の保持は directoryLister スタブで検証可能と判明したため
/// SidebarNavigatorFolderNavigationTests(unit)へ移設済み。
/// realFileSystem: true でも content ペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証はこのスイートに置かない。
@Suite
@MainActor
struct SidebarNavigatorIntegrationTests {
    private func makeController(file: URL) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, realFileSystem: true, prefix: "SidebarNavigatorIntegrationTests"
        ).controller
    }

    @Test("symlink 経由の別表記パスへの切替でも同一ディレクトリと判定され再読込が発生しない")
    func switchFileViaSymlinkAncestorKeepsCurrentDirectoryRepresentation() throws {
        let base = try makeHomeTempDir()
        defer { withExtendedLifetime(base) {} }

        // 実体ディレクトリ: base/actual/sub
        let actual = base.url.appendingPathComponent("actual", isDirectory: true)
        let subDir = actual.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let child1 = subDir.appendingPathComponent("child1.mmd")
        try "graph TD; A-->B".write(to: child1, atomically: true, encoding: .utf8)
        let child2 = subDir.appendingPathComponent("child2.mmd")
        try "graph TD; C-->D".write(to: child2, atomically: true, encoding: .utf8)

        // "actual" を指す symlink。/tmp が /private/tmp の symlink であるのと同じ構図を
        // ホームディレクトリ配下に再現する。symlink 自身を directory 引数として直接
        // 列挙すると FileManager が ENOTDIR を返す(本タスクの対象外の別問題)ため、
        // symlink を祖先(shortcut/sub)として経由する経路で検証する。
        let shortcut = base.url.appendingPathComponent("shortcut", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: actual)
        let child2ViaShortcut = shortcut.appendingPathComponent("sub").appendingPathComponent("child2.mmd")

        let controller = makeController(file: child1)
        defer { controller.close() }

        #expect(controller.fileListModel.currentDirectory.path == subDir.path)

        // 実体は同じ sub ディレクトリだが、symlink 祖先経由の別表記パスのファイルへ切り替える。
        controller.switchFile(to: child2ViaShortcut)

        #expect(controller.fileURL.lastPathComponent == "child2.mmd")
        // symlink 解決込みで同一ディレクトリと判定されるべきなので、
        // currentDirectory は shortcut 経由の表記に書き換えられず実体表記のまま保たれる。
        #expect(controller.fileListModel.currentDirectory.path == subDir.path)
        #expect(controller.fileListModel.selection?.lastPathComponent == "child2.mmd")
    }
}
