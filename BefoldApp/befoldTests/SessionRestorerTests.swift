import AppKit
@testable import befold
@testable import BefoldCLI
import Foundation
import Testing

/// TASK-73.11: パス引数なしの CLI 起動(`befold --hidden-files` 等)でも、
/// セッション復元されるウィンドウへ表示オプションが適用されることを検証する。
@Suite
@MainActor
struct SessionRestorerTests {
    private func makeRestorer(
        defaults: UserDefaults
    ) -> (restorer: SessionRestorer, manager: ViewerWindowManager, hiddenFilesPreference: HiddenFilesPreference) {
        let sessionStore = SessionStore(defaults: defaults)
        let hiddenFilesPreference = HiddenFilesPreference(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            hiddenFilesPreference: hiddenFilesPreference,
            perFileState: PerFileStateStore(defaults: defaults)
        )
        let restorer = SessionRestorer(sessionStore: sessionStore, windowManager: manager)
        return (restorer, manager, hiddenFilesPreference)
    }

    @Test("パス無しCLI起動の --hidden-files は復元直後に全体設定へ反映される")
    func hiddenFilesOptionAppliesOnRestore() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "SessionRestorerTests")
        let (restorer, manager, hiddenFilesPreference) = makeRestorer(defaults: defaults)
        SessionStore(defaults: defaults).noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showHiddenFiles: true))

        #expect(hiddenFilesPreference.showHiddenFiles)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("パス無しCLI起動の --line-numbers は復元されるウィンドウへ適用される")
    func lineNumbersOptionAppliesToRestoredWindow() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "SessionRestorerTests")
        let (restorer, manager, _) = makeRestorer(defaults: defaults)
        SessionStore(defaults: defaults).noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession(options: CLIOpenOptions(showLineNumbers: true))

        let controller = manager.controllers[file.normalizedPathKey]
        #expect(controller?.store.showLineNumbers == true)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("オプション未指定時は従来どおり復元される(既定のフォルダー優先ソート)")
    func noOptionsPreservesDefaultRestoreBehavior() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "diagram.mmd", contents: "graph TD;")
        let defaults = makeIsolatedDefaults(prefix: "SessionRestorerTests")
        let (restorer, manager, hiddenFilesPreference) = makeRestorer(defaults: defaults)
        SessionStore(defaults: defaults).noteOpened(file)

        restorer.captureSavedState()
        restorer.restoreLastSession()

        #expect(!hiddenFilesPreference.showHiddenFiles)
        #expect(manager.controllers[file.normalizedPathKey] != nil)
        manager.controllers.values.forEach { $0.close() }
    }
}
