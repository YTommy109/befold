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

    private func makeController(
        renderer: FakeDocumentRenderer,
        perFileState: PerFileStateStore? = nil,
        capabilities: @escaping () -> ViewerCapabilities = { .allEnabledForTesting }
    ) -> WebViewCommandController {
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        return WebViewCommandController(
            renderer: renderer,
            perFileState: perFileState ?? PerFileStateStore(defaults: defaults),
            currentURL: { url },
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
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        perFileState.zoom.setZoom(1.5, for: url)
        let controller = makeController(
            renderer: renderer, perFileState: perFileState, capabilities: { .none }
        )

        controller.applyStoredZoom()
        controller.applyCodeFont(family: "Menlo", points: 12)

        #expect(renderer.commands == [.applyZoom(1.5), .applyCodeFont(family: "Menlo", points: 12)])
    }

    @Test("直接 HTML モードで返った倍率だけを保存する")
    func persistsZoomReturnedByRenderer() {
        let renderer = FakeDocumentRenderer()
        let defaults = makeIsolatedDefaults(prefix: "WebViewCommandControllerTests")
        let perFileState = PerFileStateStore(defaults: defaults)
        let controller = makeController(renderer: renderer, perFileState: perFileState)

        // viewer.js が倍率を持つ通常モードでは nil が返り、保存は JS からの通知に任せる
        renderer.zoomAfterChange = nil
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == ZoomStore.defaultZoom)

        // 直接 HTML モードでは適用後の倍率が返るので、その値を保存する
        renderer.zoomAfterChange = 1.25
        controller.zoomIn()
        #expect(perFileState.zoom.zoom(for: url) == 1.25)
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
