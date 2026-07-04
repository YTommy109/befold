import AppKit
import Foundation
@testable import mmdview
import Testing

@Suite
@MainActor
struct ViewerWindowManagerTests {
    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ViewerWindowManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 一時ディレクトリに実ファイルを作り、テスト後に削除する。
    private func makeTempFile(named name: String) throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerWindowManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data("graph TD;".utf8).write(to: file)
        return (dir, file)
    }

    private func makeManager() -> ViewerWindowManager {
        let defaults = makeDefaults()
        return ViewerWindowManager(
            sessionStore: SessionStore(defaults: defaults),
            zoomStore: ZoomStore(defaults: defaults)
        )
    }

    @Test("同じファイルを二度開いてもウィンドウは 1 つに集約される")
    func openViewerReusesControllerForSamePath() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = makeManager()

        manager.openViewer(for: file)
        manager.openViewer(for: file)

        #expect(manager.controllers.count == 1)
        manager.controllers.values.forEach { $0.close() }
    }

    @Test("ウィンドウクローズで管理辞書から除去されセッション記録も閉じられる")
    func closingWindowRemovesControllerAndNotesClosed() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = makeDefaults()
        let sessionStore = SessionStore(defaults: defaults)
        let manager = ViewerWindowManager(
            sessionStore: sessionStore, zoomStore: ZoomStore(defaults: defaults)
        )

        manager.openViewer(for: file)
        #expect(sessionStore.savedURLs().map(\.normalizedPathKey) == [file.normalizedPathKey])

        manager.controllers[file.normalizedPathKey]?.close()

        #expect(manager.controllers.isEmpty)
        #expect(sessionStore.savedURLs().isEmpty)
    }

    @Test("window(forPath:) が開いたウィンドウを返す")
    func windowForPathReturnsOpenWindow() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = makeManager()

        manager.openViewer(for: file)

        let window = manager.window(forPath: file.normalizedPathKey)
        #expect(window != nil)
        let unwrappedWindow = try #require(window)
        #expect(manager.viewerPath(of: unwrappedWindow) == file.normalizedPathKey)
        manager.controllers.values.forEach { $0.close() }
    }
}
