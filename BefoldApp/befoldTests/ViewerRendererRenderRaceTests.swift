import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Foundation
import Testing

/// 描画の競合（直接 HTML モード離脱中の再発火・画像埋め込みの中断・差分の確定待ち）で
/// 描画ミラー `renderer.rendered` が正しく進むことを検証する。
///
/// **実 WKWebView は使わない（TASK-662.2）。** ここで見ているのは Swift 側のミラーだけで、
/// ミラーは送信と同じ同期区間で確定する（`ViewerScriptDispatcher`）ため、送信を記録する
/// だけのスタブ面で同じ経路を通る。実 WebView が与えていたのは「viewer.html の準備完了」の
/// 契機だけで、それは本番の `didFinish` と同じ入口 `surfaceDidFinishLoad()` で起こせる
/// （`ViewerRendererZoomProjectionTests` と同じ形）。JS 側の状態を読む検証は
/// `ViewerRendererContentUpdateIntegrationTests` に残してある。
@Suite(testTimeLimit())
@MainActor
struct ViewerRendererRenderRaceTests {
    private static let truncation = ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false)
    private static let diff = ViewerRenderer.DiffState(
        text: "diff --git a/doc.md b/doc.md\n--- a/doc.md\n+++ b/doc.md\n@@ -1 +1 @@\n-old\n+new\n",
        layout: .inline
    )

    /// viewer.html の準備が済んだ状態の renderer を返す。
    private func makeReadyRenderer() -> ViewerRenderer {
        let renderer = ViewerRenderer()
        renderer.adopt(ViewerRendererMessageStubs.Surface(), initialZoom: 1.0, findOptionsPreference: nil)
        finishLoad(renderer)
        return renderer
    }

    /// viewer.html の読み込みが終わった契機。本番で `didFinish` が通るのと同じ入口を叩く。
    private func finishLoad(_ renderer: ViewerRenderer) {
        renderer.navigationCoordinator.surfaceDidFinishLoad()
    }

    @Test("直接HTMLモード離脱の再ロード中にupdateContentが再発火しても最終的に描画される")
    func directHTMLExitSurvivesRaceDuringReload() async {
        let renderer = makeReadyRenderer()

        let fileA = URL(fileURLWithPath: "/tmp/task68-race-a.md")
        // 直接 HTML モードで fileA を表示中の状態を模す。
        renderer.directHTML.simulateForTesting(active: true, lastPath: fileA)
        renderer.recordRendered(RenderedStateMirror(filePath: fileA, isSourceMode: false))

        // 1回目: 直接HTMLモードから離脱し、viewer.html の再ロードを開始する。
        renderer.updateContent(
            "# hello", contentRevision: 7, fileType: .markdown, filePath: fileA,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        #expect(renderer.readiness.isReady == false)

        // 2回目: 再ロード中に同じ対象で再発火し、単一スロットの pendingUpdate を上書きする
        // (FileWatcher の onChange や isLoading トグル等による再発火を模す)。
        renderer.updateContent(
            "# hello", contentRevision: 7, fileType: .markdown, filePath: fileA,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )

        // 再ロード完了前は、描画ミラーが「描画済み」だと先行確定していないことを確認する。
        #expect(renderer.rendered.contentRevision == nil)

        finishLoad(renderer)
        // applyRender の画像埋め込み(withBlockingWork)は別 Task で完了するため、ミラー反映を待つ。
        await waitUntilYielding { renderer.rendered.contentRevision != nil }

        // 再ロード完了後、上書きされて残った2回目の更新が実描画され、ミラーが正しく更新される。
        #expect(renderer.rendered.contentRevision == 7)
        #expect(renderer.rendered.filePath == fileA)
    }

    /// 差分の到着で始まった applyRender が embeddedContent で中断している間に、その差分を
    /// 「反映済み」としてミラーへ先行確定してはならない。先行確定すると、同じ入力で再入した
    /// updateContent が `incoming == rendered` と判定して描画を握り潰し、同時に世代を進めるため、
    /// 中断から戻った applyRender も世代ガードで抜ける。結果、差分テキストは JS 側に入って
    /// いるのに render() が一度も走らない（TASK-334）。
    ///
    /// 中断の発生は画像埋め込みのゲートで制御する（`Task.yield()` 頼みの再現は 3 回中 1 回
    /// 素通りして未修正でも通ってしまうため、判定に使わない）。ゲートを効かせられるのは
    /// 画像埋め込みを通る markdown のレンダリング表示だけなので、判定は DOM ではなく
    /// 「握り潰しの原因になるミラーの先行確定」に置く。
    @Test("画像埋め込みでの中断中は差分を「反映済み」として先行確定しない")
    func diffStateIsNotConfirmedBeforeRender() async {
        let renderer = makeReadyRenderer()

        let markdownURL = URL(fileURLWithPath: "/tmp/task334-diff/doc.md")
        let fileReader = SlowFileReader.makeGatedImageFileReader(markdownURL: markdownURL)
        let update = {
            renderer.updateContent(
                "![alt](gated.png)", contentRevision: 1, fileType: .markdown, filePath: markdownURL,
                hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
                truncation: Self.truncation
            )
        }

        // 1 回目は素通しさせ、描画を完了させる（以降 contentRevision は変わらない）。
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(
                base: fileReader, releaseGate: BlockingGate(isOpen: true), completed: LockedBox(false)
            )
        )
        update()
        await waitUntilYielding { renderer.rendered.contentRevision == 1 }

        // 2 回目は差分が届いた状態で、埋め込みを閉じたゲートで止める
        // （埋め込みキャッシュを避けるため embedder ごと差し替える）。
        let gate = BlockingGate()
        let entered = LockedBox(false)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(
                base: fileReader, releaseGate: gate, completed: LockedBox(false), entered: entered
            )
        )
        renderer.diffState = Self.diff
        update()
        await waitUntilYielding { entered.get() }

        // 中断中はまだ「反映済み」ではない（1 回目の描画で確定した .none のまま）。
        // ここで新しい差分を先行確定していると、次の更新が握り潰される。
        #expect(renderer.rendered.diffState == ViewerRenderer.DiffState.none)

        // 実機の updateNSView 再入を模した、同じ入力での再呼び出し。
        update()
        gate.open()
        // 再入で握り潰されず、最終的に差分が反映される。
        await waitUntilYielding { renderer.rendered.diffState == Self.diff }
    }

    @Test("画像埋め込みが遅延した古いupdateContentの結果は新しい呼び出しを上書きしない")
    func staleImageEmbedDoesNotClobberNewerRender() async {
        let renderer = makeReadyRenderer()

        let markdownURL = URL(fileURLWithPath: "/tmp/task224-race/doc.md")
        let fileReader = SlowFileReader.makeGatedImageFileReader(markdownURL: markdownURL)
        // readData をゲートで足止めし、遅延埋め込みの完了タイミングをテストから明示的に制御する。
        let releaseGate = BlockingGate()
        let embedCompleted = LockedBox(false)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(base: fileReader, releaseGate: releaseGate, completed: embedCompleted)
        )

        // 1回目: 画像参照ありの content。埋め込みが releaseGate 解放まで完了しない。
        renderer.updateContent(
            "![alt](gated.png)", contentRevision: 1, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        // 2回目: 画像参照なしの content。埋め込みが不要で 1回目より先に rendered を更新する。
        renderer.updateContent(
            "no image here", contentRevision: 2, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )

        // 2回目(遅延なし)が先に完了するのを待つ。
        await waitUntilYielding { renderer.rendered.contentRevision != nil }
        #expect(renderer.rendered.contentRevision == 2)

        // 1回目の遅延埋め込みを明示的に完了させ、完了後も上書きされていないことを確認する。
        releaseGate.open()
        await waitUntilYielding { embedCompleted.get() }
        // embedLocalImages 完了から rendered への反映判定まではさらに 1 Task 分の
        // 非同期遷移があるため、MainActor を数回 yield させてから確定させる。
        await yieldMainActor()
        #expect(renderer.rendered.contentRevision == 2)
    }

    /// レンダリング表示から差分表示への切替では、差分が確定するまで前の描画を保持し、
    /// 確定後に一度で差分付きソース表示へ遷移する。ミラーの遷移列に
    /// 「isSourceMode=true + 差分なし」の中間状態(一瞬見えるプレーンなソース表示)が
    /// 現れないことを固定する(TASK-407)。
    @Test("差分が未確定の間は前の描画を保持し、確定後に一度で差分付きへ遷移する")
    func pendingDiffHoldsPreviousFrameUntilResolved() async {
        let renderer = makeReadyRenderer()
        let url = URL(fileURLWithPath: "/tmp/task407-hold/doc.md")
        let update = { (isSourceMode: Bool) in
            renderer.updateContent(
                "# doc", contentRevision: 1, fileType: .markdown, filePath: url,
                hasDeclaredHTMLCharset: nil, isSourceMode: isSourceMode, showLineNumbers: false,
                truncation: Self.truncation
            )
        }

        // 1) レンダリング表示を描画・確定させる(差分表示へ切り替える直前の状態)。
        update(false)
        await waitUntilYielding { renderer.rendered.contentRevision == 1 }
        #expect(renderer.rendered.isSourceMode == false)

        // 2) 差分表示へ切替(未確定)。描画は見送られ、ミラーは前の表示のまま動かない。
        renderer.diffState = .pending
        update(true)
        await yieldMainActor()
        #expect(renderer.rendered.isSourceMode == false)
        #expect(renderer.rendered.diffState == ViewerRenderer.DiffState.none)

        // 3) 差分が確定したら、一度の描画で差分付きソース表示へ遷移する。
        renderer.diffState = Self.diff
        update(true)
        await waitUntilYielding { renderer.rendered.diffState == Self.diff }
        #expect(renderer.rendered.isSourceMode == true)
    }
}

/// readData を意図的に足止めし、embedLocalImages(withBlockingWork 内)の完了タイミングを
/// テストから制御するためのフェイク。他のメソッドは base にそのまま委譲する。
struct SlowFileReader: FileReading {
    let base: InMemoryFileReader
    let releaseGate: BlockingGate
    let completed: LockedBox<Bool>
    /// readData へ入った（＝呼び出し元が埋め込みで中断した）ことをテストへ知らせる。
    var entered: LockedBox<Bool>?

    /// `![alt](gated.png)` を含む markdown の画像埋め込みをゲートできるファイル読み出しを作る。
    /// 中断の発生をテストから制御できる経路は画像埋め込みだけ。
    static func makeGatedImageFileReader(markdownURL: URL) -> InMemoryFileReader {
        let imageURL = markdownURL.deletingLastPathComponent().appendingPathComponent("gated.png")
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "unused"])
        fileReader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), at: imageURL)
        return fileReader
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func isDirectory(at url: URL) -> Bool {
        base.isDirectory(at: url)
    }

    func isExistingFile(at url: URL) -> Bool {
        base.isExistingFile(at: url)
    }

    func readString(from url: URL) throws -> String {
        try base.readString(from: url)
    }

    func isBinary(at url: URL) -> Bool {
        base.isBinary(at: url)
    }

    func fileSize(at url: URL) -> Int? {
        base.fileSize(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        base.modificationDate(at: url)
    }

    func readData(from url: URL) throws -> Data {
        entered?.set(true)
        releaseGate.wait("SlowFileReader.readData")
        let data = try base.readData(from: url)
        completed.set(true)
        return data
    }
}
