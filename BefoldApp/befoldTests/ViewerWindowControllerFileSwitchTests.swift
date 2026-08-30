import AppKit
@testable import befold
import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// switchFile / handleRename の副作用、すなわち「表示中ファイルの差し替えで
/// 何が更新され、何が保たれるか」を検証する unit テスト。
/// 対象はファイル URL・ウィンドウタイトル・デリゲート通知・保存済みズーム倍率・
/// ソース表示モード・描画済みミラーの filePath。
/// switchFile / performFileSwitch の存在ガードが store.fileReader 経由になった(TASK-116.12)ため、
/// InMemoryFileReader でモック化して unit で検証する。サイドバー一覧の実列挙・
/// 実 rename の再一覧に依存するテストは ViewerWindowControllerIntegrationTests に残す。
@Suite("ViewerWindowController のファイル切替・リネーム")
@MainActor
struct ViewerWindowControllerFileSwitchTests {
    @Test("switchFile でファイル URL とウィンドウタイトルが更新される")
    func switchFileUpdatesFileURLAndTitle() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let controller = makeMockedViewerWindowController(primary: file1, others: [file2])
        defer { controller.close() }

        controller.switchFile(to: file2)

        #expect(controller.fileURL == file2)
        #expect(controller.window?.title == "second.mmd")
        #expect(controller.window?.representedURL == file2)
    }

    @Test("switchFile でデリゲートに旧・新 URL が通知される")
    func switchFileInvokesDelegate() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let controller = makeMockedViewerWindowController(primary: file1, others: [file2])
        defer { controller.close() }
        let mock = MockViewerWindowControllerDelegate()
        controller.delegate = mock

        controller.switchFile(to: file2)

        #expect(mock.switchFileArgs?.old == file1)
        #expect(mock.switchFileArgs?.new == file2)
    }

    @Test("switchFile は旧・新ファイルの保存済み倍率を破壊しない")
    func switchFilePreservesSavedZoomForBothFiles() {
        let file1 = URL(fileURLWithPath: "/mock/first.mmd")
        let file2 = URL(fileURLWithPath: "/mock/second.mmd")
        let defaults = makeIsolatedDefaults(prefix: "ViewerWindowControllerTests")
        let zoomStore = ZoomStore(defaults: defaults)
        zoomStore.setZoom(2.0, for: file1)
        zoomStore.setZoom(0.75, for: file2)
        let controller = makeMockedViewerWindowController(
            primary: file1, others: [file2], zoomStore: zoomStore, defaults: defaults
        )
        defer { controller.close() }

        controller.switchFile(to: file2)

        // 切替はリネームではないため、双方の保存倍率が独立して保たれる。
        #expect(zoomStore.zoom(for: file1) == 2.0)
        #expect(zoomStore.zoom(for: file2) == 0.75)
    }

    @Test("rename 先の拡張子が対応形式かどうかでソース表示の維持/解除が決まる", arguments: [
        ("note.markdown", true), // 対応形式への rename ではソース表示が維持される
        // .swift は supportsSourceMode == false のため、ソース表示トグルが成立せずリセットする。
        ("note.swift", false), // 非対応形式への rename ではソース表示が解除される
    ])
    func renameChangesSourceModeByRenderability(renamedFilename: String, expectedSourceMode: Bool) {
        let file = URL(fileURLWithPath: "/mock/note.md")
        let controller = makeMockedViewerWindowController(primary: file, contents: "# hi")
        defer { controller.close() }
        controller.toggleSourceView(nil)
        #expect(controller.isSourceMode)
        let renamed = URL(fileURLWithPath: "/mock/\(renamedFilename)")

        controller.handleRename(from: controller.fileURL, to: renamed)

        #expect(controller.isSourceMode == expectedSourceMode)
    }

    /// handleRename → documentCommands.noteRename → WebViewProxy.renderer の配線を固定する。
    /// この配線が切れると、リネーム再ロードがファイル切替として扱われて保存済み
    /// スクロール位置が注入され、現在位置が提示開始時の値へ巻き戻る(TASK-401)。
    /// また再描画確定までのスクロール通知が migrate 済みの旧パスのキーへ保存される(TASK-393)。
    @Test("handleRename が描画済みミラーの filePath を新パスへ追随させる")
    func renameRetargetsRendererMirrorFilePath() {
        let file = URL(fileURLWithPath: "/mock/note.md")
        let controller = makeMockedViewerWindowController(primary: file, contents: "# hi")
        defer { controller.close() }
        // 本番では ViewerWebView.makeNSView が結ぶ renderer を、テストでは直接差し込む。
        let renderer = ViewerRenderer()
        renderer.recordRendered(RenderedStateMirror(filePath: file))
        controller.surfaces.web.renderer = renderer
        let renamed = URL(fileURLWithPath: "/mock/renamed.md")

        controller.handleRename(from: file, to: renamed)

        #expect(renderer.rendered.filePath == renamed)
    }
}
