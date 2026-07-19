import AppKit
@testable import befold
import Foundation
import Testing

/// SidebarNavigator のディレクトリ比較が symlink 経由でも一貫するかを実 FS で検証する。
/// `standardizedFileURL`(symlink 解決なし)と `normalizedPathKey`(symlink 解決あり)の
/// 混在で /tmp ↔ /private/tmp のようなケースが割れる問題の回帰テスト。
@Suite
@MainActor
struct SidebarNavigatorIntegrationTests {
    private func makeHomeTempDir() throws -> TempDir {
        try TempDir(base: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func makeController(file: URL) -> ViewerWindowController {
        ViewerWindowController(
            fileURL: file,
            defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorIntegrationTests"),
            perFileState: PerFileStateStore(defaults: makeIsolatedDefaults(prefix: "SidebarNavigatorIntegrationTests"))
        )
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

    @Test("親ディレクトリへ移動すると rootDirectory が最上位に更新される")
    func navigatingUpUpdatesRootDirectory() throws {
        let base = try makeHomeTempDir()
        defer { withExtendedLifetime(base) {} }

        // base/level1/level2/level3/file.mmd
        let level1 = base.url.appendingPathComponent("level1", isDirectory: true)
        let level2 = level1.appendingPathComponent("level2", isDirectory: true)
        let level3 = level2.appendingPathComponent("level3", isDirectory: true)
        try FileManager.default.createDirectory(at: level3, withIntermediateDirectories: true)
        let file = level3.appendingPathComponent("file.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let controller = makeController(file: file)
        defer { controller.close() }

        // 初期状態では rootDirectory はファイルの親ディレクトリ(level3)。
        #expect(controller.fileListModel.rootDirectory.path == level3.path)

        // level2 へ上に移動すると、そこが新たな最上位として rootDirectory に反映される。
        controller.navigateToFolder(level2)
        #expect(controller.fileListModel.rootDirectory.path == level2.path)

        // level3 へ戻っても、既に到達した最上位(level2)は保持される。
        controller.navigateToFolder(level3)
        #expect(controller.fileListModel.rootDirectory.path == level2.path)
    }

    @Test("フォルダーを選択した状態で refreshFileList してもフォルダー選択が保持される")
    func refreshFileListPreservesFolderSelection() throws {
        let base = try makeHomeTempDir()
        defer { withExtendedLifetime(base) {} }

        // base/dir/(file.mmd, sub/)
        let dir = base.url.appendingPathComponent("dir", isDirectory: true)
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("file.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let controller = makeController(file: file)
        defer { controller.close() }

        // issue #161: ファイルではなくフォルダーをサイドバーで選択した状態を再現する。
        controller.fileListModel.selection = sub

        // 他アプリへ切り替えて戻ってきた際に windowDidBecomeKey から呼ばれる処理。
        controller.sidebar.refreshFileList()

        #expect(controller.fileListModel.selection == sub)
    }
}
