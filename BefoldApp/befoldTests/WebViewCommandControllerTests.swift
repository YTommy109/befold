import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// レンダラへ「何が命じられたか」を fake で受け取り、コマンド層の方針
/// (能力による可否・結果の保存先)を検証する(ADR 0002 段 4)。
/// port を切る前は WebView 不在で全コマンドが無言の no-op になり、
/// 命令が届いたかどうかをテストで区別できなかった。
@MainActor
private final class FakeDocumentRenderer: DocumentRendering {
    enum Command: Equatable {
        case applyZoom(Double)
        case applyCodeFont(family: String?, points: Double?)
        case changeZoom(ZoomChange)
        case openFind
        case findNext
        case findPrevious
        case print
        case currentScrollPosition
    }

    private(set) var commands: [Command] = []
    var isDirectHTMLMode = false
    /// changeZoom の戻り値。直接 HTML モードの適用後倍率を模す。
    var zoomAfterChange: Double?
    /// currentScrollPosition が返す値。nil なら completion を呼ばない。
    var scrollPosition: Double?

    func applyZoom(_ zoom: Double) {
        commands.append(.applyZoom(zoom))
    }

    func applyCodeFont(family: String?, points: Double?) {
        commands.append(.applyCodeFont(family: family, points: points))
    }

    func changeZoom(_ change: ZoomChange) -> Double? {
        commands.append(.changeZoom(change))
        return zoomAfterChange
    }

    func openFind() {
        commands.append(.openFind)
    }

    func findNext() {
        commands.append(.findNext)
    }

    func findPrevious() {
        commands.append(.findPrevious)
    }

    func printDocument(over _: NSWindow?) {
        commands.append(.print)
    }

    func currentScrollPosition(_ completion: @escaping (Double) -> Void) {
        commands.append(.currentScrollPosition)
        guard let scrollPosition else { return }
        completion(scrollPosition)
    }
}

extension ZoomChange: @retroactive Equatable {}

@Suite
@MainActor
struct WebViewCommandControllerTests {
    private let url = URL(fileURLWithPath: "/tmp/a.md")

    /// 窓のライブ倍率の代役。onZoomChanged で流れてきた値を順に記録する。
    private final class ZoomChangeRecorder {
        var values: [Double] = []
    }

    private func makeController(
        renderer: FakeDocumentRenderer,
        perFileState: PerFileStateStore? = nil,
        zoomChanges: ZoomChangeRecorder = ZoomChangeRecorder(),
        capabilities: @escaping () -> ViewerCapabilities = { .allEnabledForTesting }
    ) -> WebViewCommandController {
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        return WebViewCommandController(
            renderer: renderer,
            perFileState: perFileState ?? PerFileStateStore(defaults: defaults),
            currentURL: { url },
            onZoomChanged: { zoomChanges.values.append($0) },
            capabilities: capabilities
        )
    }

    @Test("能力が無ければ、ユーザー操作はレンダラへ届かない")
    func blocksDocumentCommandsWithoutCapability() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer, capabilities: { .none })

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
        let controller = makeController(renderer: renderer)

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
        let controller = makeController(renderer: renderer, capabilities: { .none })

        controller.applyCodeFont(family: "Menlo", points: 12)

        #expect(renderer.commands == [.applyCodeFont(family: "Menlo", points: 12)])
    }

    @Test("直接 HTML モードで返った倍率だけを、窓のライブ値と保存値の両方へ反映する")
    func persistsZoomReturnedByRenderer() {
        let renderer = FakeDocumentRenderer()
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let zoomChanges = ZoomChangeRecorder()
        let controller = makeController(
            renderer: renderer, perFileState: perFileState, zoomChanges: zoomChanges
        )

        // viewer.js が倍率を持つ通常モードでは nil が返り、保存も通知も JS からの経路に任せる
        renderer.zoomAfterChange = nil
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == ZoomStore.defaultZoom)
        #expect(zoomChanges.values.isEmpty)

        // 直接 HTML モードでは適用後の倍率が返る。viewer.js からの通知が来ない経路なので、
        // ここで窓のライブ値も更新しないと画面と食い違ったまま取り残される。
        renderer.zoomAfterChange = 1.25
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == 1.25)
        #expect(zoomChanges.values == [1.25])
    }

    @Test("スクロール位置は、取得できた場合だけ指定キーへ保存する")
    func savesScrollPositionOnlyWhenAvailable() {
        let renderer = FakeDocumentRenderer()
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let controller = makeController(renderer: renderer, perFileState: perFileState)

        renderer.scrollPosition = nil
        controller.saveCurrentScrollPosition(for: url, mode: .rendered)
        #expect(perFileState.scrollPosition.scrollPosition(for: url, mode: .rendered) == 0)

        renderer.scrollPosition = 42
        controller.saveCurrentScrollPosition(for: url, mode: .rendered)
        #expect(perFileState.scrollPosition.scrollPosition(for: url, mode: .rendered) == 42)
    }

    @Test("isDirectHTMLMode はレンダラの値をそのまま反映する")
    func isDirectHTMLModeReflectsRenderer() {
        let renderer = FakeDocumentRenderer()
        let controller = makeController(renderer: renderer)
        #expect(!controller.isDirectHTMLMode)

        renderer.isDirectHTMLMode = true
        #expect(controller.isDirectHTMLMode)
    }
}
