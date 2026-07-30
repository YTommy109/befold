import AppKit
@testable import befold
@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// パス引数なしの CLI 起動(`befold --hidden-files` 等)でも、
/// セッション復元されるウィンドウへ表示オプションが適用されることを検証する。
/// SessionRestorer の存在確認とコントローラ生成パイプラインの双方を
/// MockedViewerWindowManager の InMemoryFileReader へ揃えているため実 FS を踏まない。
@Suite
@MainActor
struct SessionRestorerTests {
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    private func makeRestorer(
        _ fixture: MockedViewerWindowManager
    ) -> SessionRestorer {
        SessionRestorer(
            sessionStore: fixture.sessionStore,
            windowManager: fixture.manager,
            fileReader: fixture.fileReader
        )
    }

    @Test("パス無しCLI起動の --hidden-files は復元直後に全体設定へ反映される")
    func hiddenFilesOptionAppliesOnRestore() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showHiddenFiles: true))

        #expect(fixture.hiddenFilesPreference.showHiddenFiles)
        fixture.closeAll()
    }

    @Test("パス無しCLI起動の --line-numbers は復元されるウィンドウへ適用される")
    func lineNumbersOptionAppliesToRestoredWindow() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showLineNumbers: true))

        let controller = fixture.manager.controllers[file.normalizedPathKey]?.first
        #expect(controller?.store.showLineNumbers == true)
        fixture.closeAll()
    }

    @Test("オプション未指定時は従来どおり復元される(既定のフォルダー優先ソート)")
    func noOptionsPreservesDefaultRestoreBehavior() {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "SessionRestorerTests")
        let restorer = makeRestorer(fixture)
        fixture.sessionStore.noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession()

        #expect(!fixture.hiddenFilesPreference.showHiddenFiles)
        #expect(fixture.manager.controllers[file.normalizedPathKey] != nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成が全て実在すればタブごと復元する")
    func openRepositoryRestoresSavedTabGroupWhenAllPathsExist() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let fileB = URL(fileURLWithPath: "/repo/b.md")
        let fixture = MockedViewerWindowManager(files: [fileA, fileB], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, fileB.normalizedPathKey], selectedPath: fileB.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[fileB.normalizedPathKey] != nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成の一部が消えていれば残存パスだけで復元する")
    func openRepositoryFiltersMissingPathsFromSavedTabGroup() {
        let fileA = URL(fileURLWithPath: "/repo/a.md")
        let missing = URL(fileURLWithPath: "/repo/gone.md")
        let fixture = MockedViewerWindowManager(files: [fileA], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [fileA.normalizedPathKey, missing.normalizedPathKey], selectedPath: missing.normalizedPathKey
        )

        restorer.openRepository(root: URL(fileURLWithPath: "/repo"), savedTabGroup: group)

        #expect(fixture.manager.controllers[fileA.normalizedPathKey] != nil)
        #expect(fixture.manager.controllers[missing.normalizedPathKey] == nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成が無ければルートフォルダをサイドバー表示で開く")
    func openRepositoryFallsBackToFolderWhenNoSavedTabGroup() {
        let root = URL(fileURLWithPath: "/repo")
        let entry = URL(fileURLWithPath: "/repo/a.md")
        let fixture = MockedViewerWindowManager(files: [root, entry], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)

        restorer.openRepository(root: root, savedTabGroup: nil)

        #expect(fixture.manager.controllers[root.normalizedPathKey] != nil)
        fixture.closeAll()
    }

    @Test("保存済みタブ構成の全パスが消えていればルートフォルダにフォールバックする")
    func openRepositoryFallsBackToFolderWhenAllSavedPathsAreMissing() {
        let root = URL(fileURLWithPath: "/repo")
        let fixture = MockedViewerWindowManager(files: [root], prefix: "SessionRestorerOpenRepo")
        let restorer = makeRestorer(fixture)
        let group = SessionLayout.TabGroup(
            paths: [URL(fileURLWithPath: "/repo/gone.md").normalizedPathKey], selectedPath: nil
        )

        restorer.openRepository(root: root, savedTabGroup: group)

        #expect(fixture.manager.controllers[root.normalizedPathKey] != nil)
        fixture.closeAll()
    }
}
