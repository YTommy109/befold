import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ViewerWindowController のうち、サイドバー一覧の実列挙・実 rename の再一覧・実フォルダー
/// ナビゲーションなど、実ファイルシステムの挙動そのものを検証するテスト。DirectoryLister は
/// FileManager を直接列挙するため InMemoryFileReader でモック化できず Integration として分離する。
/// (存在ガードのみに依存する switch/rename/history/リンク遷移の unit テストは
/// ViewerWindowControllerTests へ戻した。navigateToFolder の選択ポリシー(ホーム上限ガード・
/// 子フォルダーでの自動選択抑止・親フォルダーへ戻った際の選択復元)は実列挙結果自体が本質でないため
/// SidebarNavigatorFolderNavigationTests(unit)へ移設済み。)
/// realFileSystem: true でも content ペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証はこのスイートに置かない(実コンテンツ経路は末尾のカナリアのみが例外)。
@Suite
@MainActor
struct ViewerWindowControllerIntegrationTests {
    /// テスト用に隔離済み UserDefaults(既定は使い捨て)と ZoomStore / SourceModeStore を注入したコントローラーを作る。
    /// 呼び出し側で defaults / zoomStore / sourceModeStore を後から参照したい場合は明示的に渡す。
    private func makeController(
        file: URL,
        zoomStore: ZoomStore? = nil,
        displayModeStore: DisplayModeStore? = nil,
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, realFileSystem: true, defaults: defaults,
            zoomStore: zoomStore, displayModeStore: displayModeStore
        ).controller
    }

    @Test("sidebarDisplayPreference.showHiddenFiles が true のときサイドバーに不可視ファイルが含まれる")
    func sidebarIncludesHiddenFilesWhenPreferenceIsOn() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = SidebarDisplayPreference(defaults: defaults)
        preference.showHiddenFiles = true

        let controller = ViewerWindowControllerFixture(
            file: visible, realFileSystem: true, defaults: defaults, sidebarDisplayPreference: preference
        ).controller
        defer { controller.close() }

        // 初期一覧は init 内の refreshFileList()(非同期)で埋まるため、完了を待ってから見る。
        await controller.sidebar.awaitSettled()
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains(".hidden.mmd"))
        #expect(controller.fileListModel.showHiddenFiles)
    }

    @Test("sidebarDisplayPreference.showHiddenFiles が false(デフォルト)のとき不可視ファイルは含まれない")
    func sidebarExcludesHiddenFilesWhenPreferenceIsOff() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        _ = try tmp.file(named: ".hidden.mmd", contents: "graph TD;")
        let visible = try tmp.file(named: "visible.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let preference = SidebarDisplayPreference(defaults: defaults)

        let controller = ViewerWindowControllerFixture(
            file: visible, realFileSystem: true, defaults: defaults, sidebarDisplayPreference: preference
        ).controller
        defer { controller.close() }

        await controller.sidebar.awaitSettled()
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains("visible.mmd"))
        #expect(!names.contains(".hidden.mmd"))
        #expect(!controller.fileListModel.showHiddenFiles)
    }

    @Test("rename でサイドバーの一覧が再取得され新名が選択される")
    func renameRefreshesSidebarListAndSelection() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "old.mmd", contents: "graph TD;")
        let controller = makeController(file: file)
        defer { controller.close() }
        let renamed = tmp.url.appendingPathComponent("new.mmd")
        try FileManager.default.moveItem(at: file, to: renamed)

        // 本番では ViewerStore が現在 URL(store.currentURL)を新パスへ進めてから
        // controller.handleRename を呼ぶ。その順序を再現するため store を先に進める。
        controller.store.openFile(renamed)
        controller.handleRename(from: file, to: renamed)
        await controller.sidebar.awaitSettled()

        // ディレクトリ列挙は /private シンボリックリンクを解決するため、名前で照合する。
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(controller.fileListModel.selection?.lastPathComponent == "new.mmd")
        #expect(names.contains("new.mmd"))
        #expect(!names.contains("old.mmd"))
    }

    /// このスイートの他テストはすべて ViewerWindowControllerFixture(実 WKWebView 無し)を使うが、
    /// 既定(実コンテンツ)経路そのものが壊れていないことも別途固定しておく実経路カナリア。
    @Test("既定(実コンテンツ)構成でもウィンドウが構築・クローズできる")
    func defaultContentPathBuildsWindow() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "smoke.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "Smoke")
        let controller = ViewerWindowController(
            fileURL: file,
            diffDisplayPreference: DiffDisplayPreference(defaults: defaults),
            perFileState: PerFileStateStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults)
        )
        defer { controller.close() }
        #expect(controller.window != nil)
    }
}

// MARK: - Folder Navigation

extension ViewerWindowControllerIntegrationTests {
    @Test("navigateToFolder でカレントディレクトリと一覧が更新される")
    func navigateToFolderUpdatesCurrentDirectoryAndEntries() async throws {
        let tmp = try makeHomeTempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        _ = try tmp.file(named: "sub/child.mmd", contents: "graph LR;")
        let controller = ViewerWindowControllerFixture(
            file: file, realFileSystem: true, prefix: "ViewerWindowControllerTests"
        ).controller
        defer { controller.close() }

        controller.navigateToFolder(subDir)
        await controller.sidebar.awaitSettled()

        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == subDir.standardizedFileURL)
        let names = controller.fileListModel.entries.map(\.url.lastPathComponent)
        #expect(names.contains("child.mmd"))
    }
}

// MARK: - handleOpenReference (Link Navigation)

/// 別ディレクトリへのリンク遷移でサイドバーのディレクトリが実列挙で追従することを検証する。
/// currentDirectory の追従は実 FS のディレクトリ列挙に依存するため Integration。
extension ViewerWindowControllerIntegrationTests {
    @Test("別ディレクトリへのリンク遷移でサイドバーのディレクトリが追従し、戻ると復帰する")
    func handleOpenReferenceToOtherDirectoryFollowsSidebarAndBackRestores() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let fileA = try tmp.file(named: "a.md", contents: "# A")
        let subDir = tmp.url.appendingPathComponent("sub", isDirectory: true)
        _ = try tmp.file(atPath: "sub/target.md", contents: "# Target")
        let controller = makeController(file: fileA, defaults: makeIsolatedDefaults(prefix: "OpenReference"))
        defer { controller.close() }
        let originalDirectory = controller.fileListModel.currentDirectory

        controller.handleOpenReference(href: "sub/target.md", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(controller.fileURL.lastPathComponent == "target.md")
        #expect(controller.fileListModel.currentDirectory.standardizedFileURL == subDir.standardizedFileURL)

        controller.navigateHistory(by: -1)

        #expect(controller.fileURL.lastPathComponent == "a.md")
        #expect(
            controller.fileListModel.currentDirectory.standardizedFileURL
                == originalDirectory.standardizedFileURL
        )
    }
}
