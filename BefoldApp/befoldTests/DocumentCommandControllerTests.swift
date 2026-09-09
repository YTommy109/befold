import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

@Suite
@MainActor
struct DocumentCommandControllerTests {
    @Test("能力が無ければ、ユーザー操作はレンダラへ届かない")
    func blocksDocumentCommandsWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.zoomIn()
        controller.zoomOut()
        controller.resetZoom()
        controller.openFind()
        controller.findNext()
        controller.findPrevious()
        controller.printDocument(over: nil)

        #expect(renderer.commands.isEmpty)
    }

    @Test("能力があれば、対応する命令がレンダラへ届く")
    func forwardsCommandsWhenCapable() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer)

        controller.zoomIn()
        controller.zoomOut()
        controller.resetZoom()
        controller.openFind()
        controller.findNext()
        controller.findPrevious()
        controller.printDocument(over: nil)

        #expect(renderer.commands == [
            .changeZoom(.zoomIn), .changeZoom(.zoomOut), .changeZoom(.reset),
            .openFind, .findNext, .findPrevious, .print,
        ])
    }

    @Test("設定の反映は能力で止めない(フォルダー表示中の設定変更を取り残さない)")
    func settingsAreAppliedRegardlessOfCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.applyCodeFont(family: "Menlo", points: 12)

        #expect(renderer.commands == [.applyCodeFont(family: "Menlo", points: 12)])
    }

    /// 数値表示の反映もフォントと同じく能力(ViewerCapabilities)では止めない。
    /// 止めると、フォルダーを見ている間に設定を変えた窓だけ古い表示のまま残る。
    @Test("数値表示の設定は能力に関わらず WebView へ届く")
    func appliesCsvNumberFormatRegardlessOfCapabilities() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })

        controller.applyCsvNumberFormat(grouping: false, negativeStyle: .triangleRed)

        #expect(
            renderer.commands == [.applyCsvNumberFormat(grouping: false, negativeStyle: .triangleRed)]
        )
    }

    @Test("直接 HTML モードで返った倍率だけを、窓のライブ値と保存値の両方へ反映する")
    func persistsZoomReturnedByRenderer() {
        let renderer = FakeDocumentRenderer()
        let defaults = makeIsolatedDefaults(prefix: "DocumentCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let zoomChanges = ZoomChangeRecorder()
        let controller = makeDocumentCommandController(
            renderer: renderer, perFileState: perFileState, zoomChanges: zoomChanges
        )

        // viewer.js が倍率を持つ通常モードでは nil が返り、保存も通知も JS からの経路に任せる
        renderer.zoomAfterChange = nil
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: documentCommandTestURL) == ZoomStore.defaultZoom)
        #expect(zoomChanges.values.isEmpty)

        // 直接 HTML モードでは適用後の倍率が返る。viewer.js からの通知が来ない経路なので、
        // ここで窓のライブ値も更新しないと画面と食い違ったまま取り残される。
        renderer.zoomAfterChange = 1.25
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: documentCommandTestURL) == 1.25)
        #expect(zoomChanges.values == [1.25])
    }

    /// 位置を記憶するのは窓側(`ViewerDocumentPresenter`)なので、ここは「取得できたときだけ
    /// キーごと通知する」ところまでを見る。
    @Test("スクロール位置は、取得できた場合だけ指定キーごと通知する")
    func reportsScrollPositionOnlyWhenAvailable() {
        let renderer = FakeDocumentRenderer()
        let scrollSaves = ScrollSaveRecorder()
        let controller = makeDocumentCommandController(renderer: renderer, scrollSaves: scrollSaves)

        renderer.scrollPosition = nil
        controller.saveCurrentScrollPosition(for: documentCommandTestURL, mode: .rendered)
        #expect(scrollSaves.saves.isEmpty)

        renderer.scrollPosition = 42
        controller.saveCurrentScrollPosition(for: documentCommandTestURL, mode: .rendered)
        let expected = ScrollSaveRecorder.Save(
            position: 42, url: documentCommandTestURL, mode: .rendered
        )
        #expect(scrollSaves.saves == [expected])
    }

    /// 取得完了は「そのキーと値」ごと窓へ伝える。窓はこれで記憶とライブな復元値を
    /// 追いつかせるため、値を渡さず通知だけにすると窓が読み直す形になってしまう
    /// (ADR 0002 / TASK-394)。
    @Test("保存が完了したら、保存したキーと値を窓へ伝える")
    func reportsSavedScrollPositionWithItsKey() {
        let renderer = FakeDocumentRenderer()
        let scrollSaves = ScrollSaveRecorder()
        let controller = makeDocumentCommandController(renderer: renderer, scrollSaves: scrollSaves)

        // 取得できなければ保存も通知もしない
        renderer.scrollPosition = nil
        controller.saveCurrentScrollPosition(for: documentCommandTestURL, mode: .rendered)
        #expect(scrollSaves.saves.isEmpty)

        renderer.scrollPosition = 42
        controller.saveCurrentScrollPosition(for: documentCommandTestURL, mode: .source)

        #expect(scrollSaves.saves.count == 1)
        #expect(scrollSaves.saves.first?.position == 42)
        #expect(scrollSaves.saves.first?.url == documentCommandTestURL)
        #expect(scrollSaves.saves.first?.mode == .source)
    }

    // 分割した先(いずれも file_length 対策):
    // - 統合バーの単一入口(TASK-485.19.5) → DocumentCommandController+OpenBarTests.swift
    // - 文書内ジャンプの可否と失効の同期 → DocumentCommandController+JumpTests.swift

    @Test("rename の追随は状態の反映なので能力で止めない")
    func noteRenameIsForwardedRegardlessOfCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer, capabilities: { .none })
        let renamed = URL(fileURLWithPath: "/tmp/b.md")

        controller.noteRename(from: documentCommandTestURL, to: renamed)

        #expect(renderer.commands == [.noteRename(old: documentCommandTestURL, new: renamed)])
    }

    @Test("isDirectHTMLMode はレンダラの値をそのまま反映する")
    func isDirectHTMLModeReflectsRenderer() {
        let renderer = FakeDocumentRenderer()
        let controller = makeDocumentCommandController(renderer: renderer)
        #expect(!controller.isDirectHTMLMode)

        renderer.isDirectHTMLMode = true
        #expect(controller.isDirectHTMLMode)
    }
}
