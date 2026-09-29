import AppKit
import BefoldKit
@testable import BefoldRenderKit
import Foundation
import Testing
import WebKit

/// ナビゲーション判断まわりの共有スタブ。
enum SurfaceNavigationStubs {
    /// `WebKitSurfaceEventBridge` が組み立てた `SurfaceNavigationRequest` を記録するだけの受け口。
    /// ブリッジは観測者を weak で持つので、テスト側で強参照を保つこと。
    @MainActor
    final class NavigationObserver: SurfaceNavigationObserver {
        private(set) var requests: [SurfaceNavigationRequest] = []
        private(set) var finishCount = 0
        private(set) var failCount = 0
        /// `surfaceShouldNavigate` が返す値。写像の検証では判断そのものは関係しない。
        var decision: SurfaceNavigationDecision = .cancel

        func surfaceDidFinishLoad() {
            finishCount += 1
        }

        func surfaceDidFailLoad() {
            failCount += 1
        }

        func surfaceShouldNavigate(_ request: SurfaceNavigationRequest) -> SurfaceNavigationDecision {
            requests.append(request)
            return decision
        }
    }

    /// ブリッジの初期化に要るだけの空の受け口。
    @MainActor
    final class BridgeObserver: SurfaceBridgeMessageObserver {
        private(set) var messages: [(name: String, body: Any)] = []

        func surfaceDidReceiveBridgeMessage(name: String, body: Any) {
            messages.append((name, body))
        }
    }

    /// `navigationType` / `request` / `modifierFlags` を差し替えた `WKNavigationAction`。
    /// WebKit は実際の遷移からしかこの型を作らないため、写像を単体で見るにはこの形しかない。
    final class NavigationAction: WKNavigationAction {
        private let type: WKNavigationType
        private let urlRequest: URLRequest
        private let flags: NSEvent.ModifierFlags

        init(type: WKNavigationType, url: URL?, modifiers: NSEvent.ModifierFlags = []) {
            self.type = type
            urlRequest = url.map { URLRequest(url: $0) } ?? URLRequest(url: URL(string: "about:blank")!)
            flags = modifiers
            super.init()
        }

        override var navigationType: WKNavigationType {
            type
        }

        override var request: URLRequest {
            urlRequest
        }

        override var modifierFlags: NSEvent.ModifierFlags {
            flags
        }
    }
}

/// `WKNavigationType` → `SurfaceNavigationRequest.Kind` の写像を固定する（TASK-601）。
///
/// `SurfaceEvents.swift` の doc は「**3 つに分ける。2 値へ潰さないこと。**」と書いているが、
/// TASK-595.2 で写像が `WebKitSurfaceEventBridge` へ移って以降、それを見るテストが 1 本も
/// 無かった。`default: .otherInteraction` を `.programmatic` へ寄せてもビルドも CI も通り、
/// その状態では viewer.html モードでリロード・戻る/進む・フォーム送信が `.allow` になる
/// （`DirectHTMLModeController.decidePolicy` が `.programmatic` を無条件に通すため）。
///
/// ここが落ちたら、写像を潰したということ。
@Suite
struct WebKitSurfaceEventBridgeMappingTests {
    /// 1 種類の `WKNavigationType` をブリッジへ流し、翻訳された要求を取り出す。
    @MainActor
    private static func mapKind(
        of type: WKNavigationType, url: URL? = nil, modifiers: NSEvent.ModifierFlags = []
    ) -> SurfaceNavigationRequest? {
        let navigation = SurfaceNavigationStubs.NavigationObserver()
        let bridge = SurfaceNavigationStubs.BridgeObserver()
        let eventBridge = WebKitSurfaceEventBridge(navigation: navigation, bridge: bridge)

        eventBridge.webView(
            WKWebView(),
            decidePolicyFor: SurfaceNavigationStubs.NavigationAction(
                type: type, url: url, modifiers: modifiers
            ),
            decisionHandler: { _ in }
        )
        return navigation.requests.last
    }

    @Test("リンククリックは .linkActivated へ写る")
    @MainActor
    func linkActivatedMapsToLinkActivated() {
        #expect(Self.mapKind(of: .linkActivated)?.kind == .linkActivated)
    }

    @Test("プログラムからのロード(.other)は .programmatic へ写る")
    @MainActor
    func otherMapsToProgrammatic() {
        #expect(Self.mapKind(of: .other)?.kind == .programmatic)
    }

    /// **この 4 つが本題。** どれか 1 つでも `.programmatic` へ寄ると、viewer.html モードで
    /// 黙って通るようになる。
    @Test("リロード・戻る/進む・フォーム送信は .otherInteraction へ写る")
    @MainActor
    func interactiveNavigationsMapToOtherInteraction() {
        let types: [WKNavigationType] = [.reload, .backForward, .formSubmitted, .formResubmitted]
        for type in types {
            #expect(
                Self.mapKind(of: type)?.kind == .otherInteraction,
                "navigationType \(type.rawValue) が .otherInteraction 以外へ写っている（写像を潰していないか）"
            )
        }
    }

    @Test("URL と修飾キーはそのまま渡る")
    @MainActor
    func urlAndModifiersPassThrough() {
        let url = URL(fileURLWithPath: "/tmp/task601.html")
        let request = Self.mapKind(of: .linkActivated, url: url, modifiers: [.command, .shift])
        #expect(request?.url == url)
        #expect(request?.modifiers == [.command, .shift])
    }

    /// 観測者が解放済みなら翻訳する相手が居ない。`.cancel` を返して打ち切る。
    @Test("観測者が解放済みなら .cancel を返し、要求を組み立てない")
    @MainActor
    func cancelsWhenObserverIsReleased() {
        let bridge = SurfaceNavigationStubs.BridgeObserver()
        let eventBridge: WebKitSurfaceEventBridge
        do {
            let navigation = SurfaceNavigationStubs.NavigationObserver()
            eventBridge = WebKitSurfaceEventBridge(navigation: navigation, bridge: bridge)
        }

        var decided: WKNavigationActionPolicy?
        eventBridge.webView(
            WKWebView(),
            decidePolicyFor: SurfaceNavigationStubs.NavigationAction(type: .linkActivated, url: nil),
            decisionHandler: { decided = $0 }
        )
        #expect(decided == .cancel)
    }

    @Test("観測者の判断はそのまま WebKit のポリシーへ写る")
    @MainActor
    func decisionIsForwardedToWebKit() {
        let navigation = SurfaceNavigationStubs.NavigationObserver()
        let bridge = SurfaceNavigationStubs.BridgeObserver()
        let eventBridge = WebKitSurfaceEventBridge(navigation: navigation, bridge: bridge)
        navigation.decision = .allow

        var decided: WKNavigationActionPolicy?
        eventBridge.webView(
            WKWebView(),
            decidePolicyFor: SurfaceNavigationStubs.NavigationAction(type: .other, url: nil),
            decisionHandler: { decided = $0 }
        )
        #expect(decided == .allow)

        navigation.decision = .cancel
        eventBridge.webView(
            WKWebView(),
            decidePolicyFor: SurfaceNavigationStubs.NavigationAction(type: .reload, url: nil),
            decisionHandler: { decided = $0 }
        )
        #expect(decided == .cancel)
    }
}

/// `DirectHTMLModeController.decidePolicy` の 3 分岐を、実 WKWebView 無しで見る（TASK-601）。
///
/// `SurfaceNavigationRequest` が WebKit 非依存の値になったので、fake の描画面
/// （`ViewerRendererMessageStubs.Surface`）だけで判断を丸ごと組める。それがこの境界を
/// 入れた目的そのもの。
@Suite
struct DirectHTMLDecidePolicyTests {
    private static let documentURL = URL(fileURLWithPath: "/tmp/task601-doc.html")
    /// 同一文書内のフラグメント。`DirectHTMLLinkPolicy` が唯一 `.allow` へ倒す入力なので、
    /// 「分類まで届いたか」を判定の有無から見分けるのに使う。
    private static let fragmentURL = URL(string: documentURL.absoluteString + "#section")!

    @MainActor
    private static func makeRenderer(
        _ surface: ViewerRendererMessageStubs.Surface, directHTMLActive: Bool
    ) -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.surface = surface
        surface.currentURL = documentURL
        renderer.directHTML.simulateForTesting(
            active: directHTMLActive, lastPath: directHTMLActive ? documentURL : nil
        )
        return renderer
    }

    @MainActor
    private static func decide(
        renderer: ViewerRenderer, surface: ViewerRendererMessageStubs.Surface,
        kind: SurfaceNavigationRequest.Kind, url: URL?,
        modifiers: NSEvent.ModifierFlags = []
    ) -> SurfaceNavigationDecision {
        renderer.directHTML.decidePolicy(
            surface: surface,
            request: SurfaceNavigationRequest(kind: kind, url: url, modifiers: modifiers)
        )
    }

    // MARK: - 1 つ目の分岐: プログラムからのロードは通す

    @Test("プログラムからのロードは、直接 HTML モードでなくても通す")
    @MainActor
    func programmaticIsAllowedInViewerHTMLMode() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: false)

        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .programmatic, url: Self.documentURL
        )
        #expect(decided == .allow)
    }

    @Test("プログラムからのロードは、直接 HTML モードでも通す")
    @MainActor
    func programmaticIsAllowedInDirectHTMLMode() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: true)

        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .programmatic, url: Self.documentURL
        )
        #expect(decided == .allow)
    }

    // MARK: - 2 つ目の分岐: viewer.html モードではロード以外を全て止める

    /// `.otherInteraction`（リロード・戻る/進む・フォーム送信）がここで止まることが、
    /// 写像を 3 値に保つ理由そのもの。
    @Test("viewer.html モードでは、プログラムのロード以外を全て止める")
    @MainActor
    func viewerHTMLModeCancelsEverythingButProgrammatic() {
        for kind in [SurfaceNavigationRequest.Kind.linkActivated, .otherInteraction] {
            let surface = ViewerRendererMessageStubs.Surface()
            let renderer = Self.makeRenderer(surface, directHTMLActive: false)

            let decided = Self.decide(
                renderer: renderer, surface: surface, kind: kind, url: Self.documentURL
            )
            #expect(decided == .cancel, "viewer.html モードで \(kind) が通っている")
        }
    }

    // MARK: - 3 つ目の分岐: 直接 HTML モードではリンククリックだけを分類する

    /// URL は**同一文書内のフラグメント**を渡す。`DirectHTMLLinkPolicy` はこれを
    /// `.allowNativeNavigation` に分類するので、`kind == .linkActivated` の判定が抜けると
    /// ここが `.allow` になって落ちる（実測: 判定を外すと落ちることを確認済み）。
    /// 他のローカルファイルを渡すと分類の結果も `.cancel` なので、判定の有無を区別できない。
    @Test("直接 HTML モードでも、リンククリック以外は分類せず止める")
    @MainActor
    func directHTMLModeCancelsNonLinkInteraction() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: true)
        let delegate = ViewerRendererMessageStubs.Delegate()
        renderer.delegate = delegate
        var openedReference = false
        delegate.onOpenReference = { _, _ in openedReference = true }

        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .otherInteraction,
            url: Self.fragmentURL
        )

        #expect(decided == .cancel, "リンククリック以外がリンク分類へ流れている")
        #expect(openedReference == false)
    }

    @Test("URL の無いリンククリックは止める")
    @MainActor
    func directHTMLModeCancelsLinkWithoutURL() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: true)

        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .linkActivated, url: nil
        )
        #expect(decided == .cancel)
    }

    @Test("同一文書内のフラグメントは、ネイティブのスクロールへ通す")
    @MainActor
    func directHTMLModeAllowsSameDocumentFragment() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: true)

        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .linkActivated,
            url: Self.fragmentURL
        )
        #expect(decided == .allow)
    }

    @Test("他のローカルファイルへのリンクは、アプリ側で開いて遷移自体は止める")
    @MainActor
    func directHTMLModeOpensLocalFileThroughDelegate() {
        let surface = ViewerRendererMessageStubs.Surface()
        let renderer = Self.makeRenderer(surface, directHTMLActive: true)
        let delegate = ViewerRendererMessageStubs.Delegate()
        renderer.delegate = delegate
        var opened: (path: String, disposition: OpenDisposition)?
        delegate.onOpenReference = { opened = ($0, $1) }

        let target = URL(fileURLWithPath: "/tmp/task601-other.html")
        let decided = Self.decide(
            renderer: renderer, surface: surface, kind: .linkActivated, url: target,
            modifiers: [.command]
        )

        #expect(decided == .cancel)
        #expect(opened?.path == target.path)
        #expect(opened?.disposition == .newTab)
    }
}
