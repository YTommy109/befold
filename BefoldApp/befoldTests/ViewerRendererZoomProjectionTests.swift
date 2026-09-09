import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// 初期倍率が「生成時に焼き込む値」ではなく「状態の投影」として適用されることを検証する
/// (ADR 0002 段 3 / TASK-270)。
///
/// ウィンドウの生成が表示対象の確定より先に走る経路があるため、面を作る時点では
/// 正しい倍率が分からないことがある。準備完了時と、準備後に値が変わった時の双方で
/// 適用し直せていることを見る。
///
/// **実 WKWebView は使わない（TASK-607）。** かつては実 WebView を作り、本物の
/// `didFinish` が届くのを待っていたが、この suite が確かめているのは
/// `renderer.pageZoom.applied` という **Swift 側の状態**だけで、JS を覗くアサートは
/// 1 つも無かった（唯一 WebView に触るヘルパー `currentZoom(in:)` は定義されたまま
/// 一度も呼ばれていなかった）。実 WebView が与えていたのは「準備完了の契機」だけで、
/// それは本番と同じ `navigationCoordinator.surfaceDidFinishLoad()` で直接起こせる。
///
/// 実 WebView を持つ代償は大きかった。WebKit のコールバックはメインキュー経由で届くため、
/// 並列実行で ~1900 件の `@MainActor` テストがキューを埋めると着地が後ろへ回され、
/// 実測では `loadFileURL` 25 回に対し `didFinish` が 35 秒間 1 件も届かず、実行の最後に
/// まとめて着地した。待機予算を延ばしても間に合わない形の間欠失敗になっていた。
/// 契機を直接起こす形にすると待つ必要そのものが無くなり、決定的になる。
@Suite
@MainActor
struct ViewerRendererZoomProjectionTests {
    private static let truncation = ViewerRenderer.TruncationState(
        isTruncated: false, lineCount: 1, failed: false
    )

    /// 面を結びつけた renderer を返す。**面は記録するだけのスタブ**で、WebKit の
    /// プロセスも viewer.html も要らない。
    private func makeRenderer(initialZoom: Double = 1.0) -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.adopt(
            ViewerRendererMessageStubs.Surface(),
            initialZoom: initialZoom, findOptionsPreference: nil
        )
        return renderer
    }

    /// viewer.html の読み込みが終わった契機。本番で `didFinish` が通るのと同じ入口を叩く。
    private func finishLoad(_ renderer: ViewerRenderer) {
        renderer.navigationCoordinator.surfaceDidFinishLoad()
    }

    @Test("生成後に倍率が確定しても、viewer.html の準備完了時に適用される")
    func appliesZoomDecidedAfterCreation() {
        // 生成時点では対象ファイルが未確定で、既定倍率しか渡せない状況を再現する。
        let renderer = makeRenderer()

        // 対象が確定して保存倍率が判明した(updateNSView が値を流し込んだ)状態。
        renderer.initialPageZoom = 1.5

        finishLoad(renderer)

        #expect(renderer.readiness.isReady)
        // 準備完了までに値が変わっていた場合でも、適用済みとして記録されている。
        #expect(renderer.pageZoom.applied == 1.5)
    }

    /// **倍率は代入では当たらず、その文書が描かれるときに当たる。**
    ///
    /// ホストはファイルを切り替えた時点で新しいファイルの倍率を流し込むが、その瞬間に
    /// 画面へ出ているのはまだ前のファイル（面の宛先は描画が確定した種別で切り替わる）。
    /// 代入で即座に当てると、切り替わる前のファイルの倍率が変わってから新しい
    /// ファイルが出る、というちらつきになる（TASK-567 の実測）。
    @Test("倍率は代入では当たらず、次に描かれるときに当たる")
    func appliesZoomWhenTheDocumentIsRendered() async {
        let renderer = makeRenderer()
        renderer.isVisible = true
        finishLoad(renderer)
        #expect(renderer.pageZoom.applied == 1.0)

        // 切り替え先の倍率が流し込まれた直後。まだ前の文書が出ているので当てない。
        renderer.initialPageZoom = 0.75
        #expect(renderer.pageZoom.applied == 1.0)

        // 新しい内容が描かれると、内容と同じ区間で当たる。
        // markdown を避ける理由は下のテストの doc を参照(非同期の画像埋め込みを通らせない)。
        renderer.updateContent(
            "graph TD;", contentRevision: 1, fileType: .mmd,
            filePath: URL(fileURLWithPath: "/files/a.mmd"), hasDeclaredHTMLCharset: nil,
            isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 30)) {
            renderer.pageZoom.applied == 0.75
        }
        #expect(renderer.pageZoom.applied == 0.75)
    }

    /// **切り替え直後の `updateContent` は前のファイルに対する `.skip` である。**
    /// そこで当てると、まだ画面に出ている前のファイルの倍率が変わる（TASK-567 の実測。
    /// PDF へ切り替えるときに「Markdown の倍率が変わってから PDF が出る」形で見えた）。
    @Test("内容に差が無い更新では倍率を当てない")
    func doesNotApplyZoomWhenNothingIsRedrawn() async {
        let renderer = makeRenderer()
        renderer.isVisible = true
        finishLoad(renderer)
        // **markdown を使わない。** markdown だけがローカル画像の data URI 差し替え
        // (`MarkdownImageEmbedder`、MainActor 外)を通るため、`rendered` の更新が非同期になり
        // フル実行の負荷下で 1 度目の描画が着地する前に 2 度目を送ってしまう
        // (実測: `contentRevision == 1` の待機が予算切れし、`.skip` にならず倍率が当たった)。
        // このテストが見たいのは「差が無ければ当てない」という計画の判断だけで、種別は問わない。
        let file = URL(fileURLWithPath: "/files/a.mmd")

        renderer.updateContent(
            "graph TD;", contentRevision: 1, fileType: .mmd, filePath: file,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )
        // 描画は種別によらず非同期（`applyRender` が常に `await embeddedContent` を通る）。
        // **ここで待つのは正当**——WebKit のロード待ちと違い、これは Swift 側の仕事なので
        // スリープでも前進する。予算を既定の 10 秒より厚く取るのは、フル実行の並列負荷で
        // MainActor 外の埋め込みが遅れて予算切れした実測があるため。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 30)) {
            renderer.rendered.contentRevision == 1
        }

        // 切り替え先の倍率が流し込まれ、同じ内容でもう一度呼ばれた状態を模す。
        renderer.initialPageZoom = 0.5
        renderer.updateContent(
            "graph TD;", contentRevision: 1, fileType: .mmd, filePath: file,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
            truncation: Self.truncation
        )

        #expect(renderer.pageZoom.applied == 1.0)
    }

    @Test("同じ倍率を流し込んでも再適用はしない")
    func doesNotReapplyIdenticalZoom() {
        let renderer = makeRenderer(initialZoom: 1.25)
        finishLoad(renderer)
        #expect(renderer.pageZoom.applied == 1.25)

        renderer.pageZoom.invalidateApplied()
        renderer.initialPageZoom = 1.25
        // 代入では当たらないので、記録は捨てたまま。
        #expect(renderer.pageZoom.applied == nil)
    }
}
