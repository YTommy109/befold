import AppKit
import Foundation
@testable import mmdview
import Testing

@Suite
@MainActor
struct ViewerWindowControllerTests {
    /// テストごとに独立した UserDefaults スイートを用意する。
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ViewerWindowControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 一時ディレクトリに実ファイルを作り、テスト後に削除する。
    private func makeTempFile(named name: String) throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewerWindowControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data("graph TD;".utf8).write(to: file)
        return (dir, file)
    }

    /// NSWindowController.init(window:) はウィンドウの frameAutosaveName を
    /// コントローラ側の windowFrameAutosaveName（既定は空）で上書きするため、
    /// init 完了後もファイル毎の autosave 名が残っていることを検証する。
    /// これが空だと AppKit の frame autosave が一切動かず、
    /// ウィンドウ位置・サイズがファイル毎に保存されない。
    @Test("フレーム autosave 名が init 完了後もファイル毎の名前で維持される")
    func frameAutosaveNameSurvivesInit() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }

        let controller = ViewerWindowController(fileURL: file, zoomStore: ZoomStore(defaults: makeDefaults()))
        defer { controller.close() }

        let expected = "Viewer-" + file.normalizedPathKey.replacingOccurrences(of: "/", with: "_")
        #expect(controller.window?.frameAutosaveName == expected)
        #expect(controller.windowFrameAutosaveName == expected)
    }

    /// フレーム autosave 名も ZoomStore と同じ正規化パス基準を使い、
    /// シンボリックリンク経由で開いても実体パスと同じキーに集約されることを検証する。
    @Test("シンボリックリンク経由で開いてもフレーム autosave 名は実体パス基準になる")
    func frameAutosaveNameResolvesSymlinks() throws {
        let (dir, real) = try makeTempFile(named: "real.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("link.mmd")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let controller = ViewerWindowController(fileURL: link, zoomStore: ZoomStore(defaults: makeDefaults()))
        defer { controller.close() }

        let expected = "Viewer-" + real.normalizedPathKey.replacingOccurrences(of: "/", with: "_")
        #expect(controller.windowFrameAutosaveName == expected)
    }

    @Test("windowDidBecomeKey で onBecomeKey コールバックが呼ばれる")
    func windowDidBecomeKeyInvokesCallback() throws {
        let (dir, file) = try makeTempFile(named: "diagram.mmd")
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = ViewerWindowController(fileURL: file, zoomStore: ZoomStore(defaults: makeDefaults()))
        defer { controller.close() }
        var becameKey = false
        controller.onBecomeKey = { becameKey = true }

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        #expect(becameKey)
    }
}
