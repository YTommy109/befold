import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 実 WKWebView をロードし、中断された描画が JS 側 `_mmdViewOptions` に値を送り残さない
/// ことを検証する回帰テスト。判定を JS 側に置くため実ロード完了を待つ必要があり、
/// Integration に分離する(判定基準は docs/dev/coding_rule.md の「Unit / Integration の分離」節を参照)。
/// Swift 側のミラーだけを見る競合テストは `ViewerRendererRenderRaceTests` へ移した(TASK-662.2)。
@Suite(testTimeLimit())
@MainActor
struct ViewerRendererContentUpdateIntegrationTests {
    /// 実 WKWebView のロード完了を待つ。**yield スピン自体がメインランループを回して
    /// ロードを前進させる**ため、この待ちだけは上限つきヘルパーを使わない。
    ///
    /// 実測: 回数上限(既定 100_000)を付けるとフル実行の負荷下で完了前に打ち切られ、
    /// 約 30〜50% でフレークする(単独実行では常に成立するため単独では検出できない)。
    /// 上限を 20_000_000 まで上げるとフレークは減るが、成立しない回のスピンが分単位になる。
    /// 時間ベース(`waitUntilOnMainActor`)は予算 60 秒でも成立しない——スリープでは
    /// ランループが回らずロードが前進しないため。
    ///
    /// ハング対策はスイートの `testTimeLimit()` が担う。上限を外した無限ループにしない
    /// 一般則(テスト規約)に対する、この経路固有の例外として扱う。
    @MainActor
    private static func waitForWebViewLoad(_ condition: () -> Bool) async {
        while !condition() {
            await Task.yield()
        }
    }

    private static let truncation = ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false)

    /// 中断された applyRender は、表示オプションを JS へ送ってはならない。送ってから
    /// 世代ガードで抜けるとミラーへ確定されず、以後の applyRender が「ミラーと同値」と
    /// 見て再送をスキップするため、JS 側に中断時の値が残り続ける(TASK-336)。
    ///
    /// 描画中に差分表示を ON→OFF した状況を作り、JS が保持する差分を直接読んで測る。
    /// ミラーだけを見ると「.none のまま」で両実装が同じに見えるため、判定は JS 側に置く。
    @Test("中断された描画は表示オプションを JS へ送り残さない")
    func abortedRenderDoesNotLeaveOptionsInJS() async throws {
        let renderer = ViewerRenderer()
        let webView = ViewerRendererMessageStubs.makeWebView(with: renderer)
        await Self.waitForWebViewLoad { renderer.readiness.isReady }

        let markdownURL = URL(fileURLWithPath: "/tmp/task336-abort/doc.md")
        let fileReader = SlowFileReader.makeGatedImageFileReader(markdownURL: markdownURL)
        let content = "![alt](gated.png)"
        let update = {
            renderer.updateContent(
                content, contentRevision: 1, fileType: .markdown, filePath: markdownURL,
                hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
                truncation: Self.truncation
            )
        }

        // 1 回目は素通しさせ、差分なしの状態で描画を完了させる。
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(
                base: fileReader, releaseGate: BlockingGate(isOpen: true), completed: LockedBox(false)
            )
        )
        update()
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision == 1 }

        // 2 回目: 差分 ON で描画を始め、画像埋め込みのゲートで中断させる。
        let gate = BlockingGate()
        let entered = LockedBox(false)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(
                base: fileReader, releaseGate: gate, completed: LockedBox(false), entered: entered
            )
        )
        let diffText = "diff --git a/doc.md b/doc.md\n--- a/doc.md\n+++ b/doc.md\n@@ -1 +1 @@\n-old\n+new\n"
        renderer.diffState = ViewerRenderer.DiffState(text: diffText, layout: .inline)
        update()
        await Self.waitForWebViewLoad { entered.get() }

        // 中断中に差分を OFF へ戻す。この更新は incoming == rendered(差分なしのまま)で
        // 早期 return するが、世代だけは進むため、中断していた 2 回目は世代ガードで抜ける。
        renderer.diffState = .none
        update()
        gate.open()
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision == 1 }
        await yieldMainActor()

        // ミラーは「差分なし」を指している。JS も同じでなければ、次の描画で
        // 再送がスキップされて中断時の差分が描かれる。
        #expect(renderer.rendered.diffState == ViewerRenderer.DiffState.none)
        let diffInJS = try await webView.evaluateJavaScript("String(_mmdViewOptions.diff())")
        #expect(diffInJS as? String == "null")

        // 上の判定が「JS を読めていないだけ」で通っていないことを、同じ読み出しで確かめる
        // (差分を実際に反映させれば同じ式が本文を返す)。
        renderer.diffState = ViewerRenderer.DiffState(text: diffText, layout: .inline)
        renderer.updateContent(
            content, contentRevision: 2, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision == 2 }
        let appliedDiffInJS = try await webView.evaluateJavaScript("String(_mmdViewOptions.diff())")
        #expect(appliedDiffInJS as? String == diffText)
    }
}
