import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ViewerWindowController のうち、ウィンドウそのものの振る舞い
/// (初期状態・デリゲート通知・メニュー状態・WindowFrameStore へのフレーム記録)を検証する
/// unit テスト。store に InMemoryFileReader + MockFileWatcher を注入して実 FS を使わない。
/// 実 rename/switch/navigate/隠しファイルフィルタに依存するテストは
/// ViewerWindowControllerIntegrationTests へ移した。
/// コンテンツペインはプレースホルダ(ViewerWindowControllerFixture)のため、
/// WebView に依存する検証(検索・印刷・ズームなど)はこのスイートに置かない。
/// ファイル切替・履歴・参照解決は ViewerWindowControllerFileSwitchTests /
/// ViewerWindowControllerHistoryTests / ViewerWindowControllerRefResolutionTests /
/// ViewerWindowControllerReferenceOpenTests に分割した。
@Suite("ViewerWindowController のウィンドウ初期状態とフレーム記録")
@MainActor
struct ViewerWindowControllerTests {
    /// 実在しない合成パス。InMemoryFileReader にだけ登録する。
    private let file = URL(fileURLWithPath: "/mock/diagram.mmd")

    /// テスト用に隔離済み UserDefaults とモック済み store(実 WKWebView 無し)を注入したコントローラーを作る。
    private func makeController(
        defaults: UserDefaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(file: file, defaults: defaults).controller
    }

    /// 互いに独立した(状態を共有・変更し合わない)初期状態の検証をまとめて
    /// 1つのウィンドウ生成で行う: frameAutosaveName 未設定・デフォルトコンテンツサイズ・
    /// windowDidBecomeKey 通知・switchFile の同一ファイル無視・初期履歴が空・
    /// ブックマークメニューのトグル。
    @Test("新規ウィンドウの初期状態(フレーム・デリゲート通知・履歴・メニュー)を検証する")
    func newWindowInitialState() {
        let controller = makeController()
        defer { controller.close() }

        // ファイル別の frameAutosaveName は設定されない
        #expect(controller.windowFrameAutosaveName == "")

        // 保存されたフレームがなければデフォルトのコンテンツサイズで開く
        let contentSize = controller.window.map {
            $0.contentRect(forFrameRect: $0.frame).size
        } ?? .zero
        #expect(contentSize == NSSize(width: 1100, height: 850))

        // windowDidBecomeKey でデリゲートが呼ばれる
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(mock.becomeKeyCalled)

        // switchFile で同じファイルを選んでも何も起きない
        controller.switchFile(to: file)
        #expect(mock.switchFileArgs == nil)

        // 初期状態では戻る履歴がない
        #expect(controller.canGoBack == false)
        #expect(controller.canGoForward == false)

        // ブックマークメニューはブックマーク状態に応じてタイトルが切り替わる
        let bookmarkItem = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.toggleBookmark(_:)), keyEquivalent: ""
        )
        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.addBookmark", bundle: .l10n))
        controller.toggleBookmark(nil)
        #expect(controller.validateMenuItem(bookmarkItem) == true)
        #expect(bookmarkItem.title == String(localized: "menu.view.removeBookmark", bundle: .l10n))
    }

    // フレームの「次のウィンドウへの引き継ぎ」自体は ViewerWindowManager.openViewer が
    // WindowFrameStore を介して解決する(ViewerWindowManagerIntegrationTests 参照)。ここでは
    // ViewerWindowController 自身の責務、すなわち (1) リサイズ/クローズ時に
    // WindowFrameStore へ記録すること、(2) 注入された initialFrameDescriptor を
    // 実際のウィンドウへ適用すること、を検証する。

    @Test("リサイズ完了時に WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnResize() {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let fixture = ViewerWindowControllerFixture(file: file, defaults: defaults)
        let controller = fixture.controller
        defer { controller.close() }
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        controller.window?.setFrame(frame, display: false)

        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == controller.window?.frameDescriptor)
    }

    @Test("ウィンドウを閉じたときにも WindowFrameStore へフレームが記録される")
    func windowFrameIsRecordedOnClose() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let fixture = ViewerWindowControllerFixture(file: file, defaults: defaults)
        let controller = fixture.controller
        let frame = NSRect(x: 160, y: 180, width: 800, height: 650)
        controller.window?.setFrame(frame, display: false)
        let descriptor = try #require(controller.window?.frameDescriptor)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        controller.close()

        #expect(fixture.perFileState.windowFrame.frameDescriptor(for: file) == descriptor)
    }

    @Test("initialFrameDescriptor を渡すとそのフレームで開く")
    func windowUsesInjectedInitialFrameDescriptor() throws {
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let first = makeController(defaults: defaults)
        let frame = NSRect(x: 120, y: 140, width: 900, height: 700)
        first.window?.setFrame(frame, display: false)
        let descriptor = try #require(first.window?.frameDescriptor)
        first.close()

        let second = ViewerWindowControllerFixture(
            file: file, defaults: defaults, initialFrameDescriptor: descriptor
        ).controller
        defer { second.close() }

        #expect(second.window?.frame == frame)
    }
}
