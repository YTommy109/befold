import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
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
        // 1 件目の解決をゲートで止め、2 件目のディスパッチ後に解放する。固定 sleep で
        // 「この程度待てば追い越すはず」と期待する代わりに、追い越しの状況を決定的に作る。
        let slowResolution = AsyncGate()
        delegate.onResolveReferences = { _ in
            guard isFirstRequest else { return secondResult }
            isFirstRequest = false
            await slowResolution.wait()
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
        slowResolution.open()
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

    /// ページを読み直すと JS 側のキュー(_mmdPendingRefBatches)は空になる。飛行中の応答を
    /// そのまま評価すると、新しいページが積んだ別のバッチへ古いマップが当たり、実在する
    /// パスまで解決失敗表示(befold-link-dead)になる。読み直しをまたいだ応答は捨てる。
    @Test("ページを読み直したら、飛行中の解決応答は評価しない")
    func resolveReferencesDropsResponseAcrossPageReload() async {
        let renderer = ViewerRenderer()
        let webView = Stubs.WebView()
        renderer.webView = webView
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        let slowResolution = AsyncGate()
        // 解決の「最中」に読み直しを起こす。要求受付時点で判定しても素通りする窓であり、
        // 実際に報告された経路（git 解決を待つ間にユーザーが .html へ切り替えて戻る）と同じ。
        var isResolving = false
        delegate.onResolveReferences = { _ in
            isResolving = true
            await slowResolution.wait()
            return ["./old.md": "/repo/old.md"]
        }

        Stubs.dispatch(
            renderer, name: ViewerBridge.resolveReferencesMessageName,
            body: ["paths": ["./old.md"]]
        )
        _ = await waitUntilOnMainActor(timeout: testTimeout(fallback: 5)) { isResolving }
        // 直接 HTML モードからの復帰。ここで viewer.html を読み直し、JS の状態が捨てられる。
        renderer.exitDirectHTMLMode(webView: webView) {}
        slowResolution.open()
        await renderer.resolveResponseChain?.value

        let applied = webView.evaluatedScripts.filter {
            $0 == ViewerBridge.applyResolvedReferencesScript(["./old.md": "/repo/old.md"])
        }
        #expect(applied.isEmpty, "読み直し前の応答が、新しいページのバッチへ適用される")
    }

    /// 上の破棄が広すぎないことを担保する。読み直しをまたがない要求は、読み直しの後に
    /// 出したものも含めて従来どおり応答される(応答が来ないと pending のまま固まる)。
    @Test("読み直しの後に出した要求は、従来どおり応答される")
    func resolveReferencesStillRepliesForCurrentPage() async {
        let renderer = ViewerRenderer()
        let webView = Stubs.WebView()
        renderer.webView = webView
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        delegate.onResolveReferences = { _ in ["./new.md": "/repo/new.md"] }

        renderer.exitDirectHTMLMode(webView: webView) {}
        Stubs.dispatch(
            renderer, name: ViewerBridge.resolveReferencesMessageName,
            body: ["paths": ["./new.md"]]
        )
        await renderer.resolveResponseChain?.value

        #expect(
            webView.lastEvaluatedScript
                == ViewerBridge.applyResolvedReferencesScript(["./new.md": "/repo/new.md"])
        )
    }
}
