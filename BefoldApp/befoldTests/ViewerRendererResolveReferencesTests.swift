import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// 表示時パス解決 (resolveReferences) のブリッジを検証する。
/// JS 側は応答を要求へ FIFO で対応づけるため、「要求 1 つにつき応答 1 つ」「要求順 = 応答順」の
/// 2 つが崩れると、解決結果が別のバッチへ当たって実在するパスまで解決失敗表示になる。
@Suite
@MainActor
struct ViewerRendererResolveReferencesTests {
    private typealias Stubs = ViewerRendererMessageStubs

    @Test("resolveReferences が onResolveReferences へ paths を渡し、解決結果を適用スクリプトで評価する")
    func resolveReferencesDispatchesPathsAndAppliesResult() async {
        let renderer = ViewerRenderer()
        let webView = Stubs.WebView()
        renderer.webView = webView
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        var receivedPaths: [String]?
        delegate.onResolveReferences = { paths in
            receivedPaths = paths
            return ["./other.md": "/repo/other.md"]
        }

        Stubs.dispatch(
            renderer, name: ViewerBridge.resolveReferencesMessageName,
            body: ["paths": ["./other.md", "./missing.md"]]
        )
        await renderer.resolveResponseChain?.value

        #expect(receivedPaths == ["./other.md", "./missing.md"])
        #expect(
            webView.lastEvaluatedScript
                == ViewerBridge.applyResolvedReferencesScript(["./other.md": "/repo/other.md"])
        )
    }

    /// 解決は git subprocess を伴いうるため非同期であり、要求ごとに所要時間が違う。
    /// 完了順にそのまま応答すると FIFO の対応づけが崩れる。
    /// 直列チェーン (resolveResponseChain) を外すとこのテストが落ちる。
    @Test("解決が遅い要求が先にあっても、応答は要求と同じ順序で評価される")
    func resolveReferencesRepliesInRequestOrder() async {
        let renderer = ViewerRenderer()
        let webView = Stubs.WebView()
        renderer.webView = webView
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        let firstResult = ["./slow.md": "/repo/slow.md"]
        let secondResult = ["./fast.md": "/repo/fast.md"]
        var isFirstRequest = true
        delegate.onResolveReferences = { _ in
            guard isFirstRequest else { return secondResult }
            isFirstRequest = false
            // 1 件目の解決だけ遅らせ、2 件目が追い越しうる状況を作る。
            try? await Task.sleep(for: .milliseconds(50))
            return firstResult
        }

        Stubs.dispatch(
            renderer, name: ViewerBridge.resolveReferencesMessageName,
            body: ["paths": ["./slow.md"]]
        )
        Stubs.dispatch(
            renderer, name: ViewerBridge.resolveReferencesMessageName,
            body: ["paths": ["./fast.md"]]
        )
        await renderer.resolveResponseChain?.value

        #expect(
            webView.evaluatedScripts == [
                ViewerBridge.applyResolvedReferencesScript(firstResult),
                ViewerBridge.applyResolvedReferencesScript(secondResult),
            ]
        )
    }

    /// ペイロードが不正でも応答は必ず返す必要がある。落とすとキューが恒久的にずれ、
    /// 以後すべての参照が解決失敗表示になる。解決自体はアプリ層へ渡さず、空の結果で応答する。
    @Test("resolveReferences のペイロードが不正でも空の適用スクリプトを必ず評価する")
    func resolveReferencesAlwaysRepliesOnInvalidPayload() async {
        // 不正ペイロードの各形: キー欠落・型違い・要素の型違い。
        let invalidBodies: [Any] = [
            [String: Any](),
            ["paths": "not-an-array"],
            ["paths": [1, 2]],
            "not-an-object",
        ]

        for body in invalidBodies {
            let renderer = ViewerRenderer()
            let webView = Stubs.WebView()
            renderer.webView = webView
            let delegate = Stubs.Delegate()
            renderer.delegate = delegate
            var called = false
            delegate.onResolveReferences = { _ in
                called = true
                return ["./a.md": "/repo/a.md"]
            }

            Stubs.dispatch(renderer, name: ViewerBridge.resolveReferencesMessageName, body: body)
            await renderer.resolveResponseChain?.value

            #expect(called == false, "不正ペイロードをアプリ層へ渡している: \(body)")
            #expect(
                webView.lastEvaluatedScript == ViewerBridge.applyResolvedReferencesScript([:]),
                "応答を返していない: \(body)"
            )
        }
    }
}
