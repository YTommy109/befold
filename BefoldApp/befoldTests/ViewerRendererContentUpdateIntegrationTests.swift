import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// 実 WKWebView をロードして直接HTMLモード離脱時の再描画競合・画像埋め込み競合・
/// コードフォント注入スクリプトを検証する回帰テスト。WebKit の実ロード完了を
/// 待つ必要があり、テスト対象自体を差し替えられないため Integration に分離する
/// (判定基準は docs/dev/coding_rule.md の「Unit / Integration の分離」節を参照)。
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

    /// `![alt](gated.png)` を含む markdown の画像埋め込みを SlowFileReader でゲートできる
    /// ファイル読み出しを作る。中断の発生をテストから制御できる経路は画像埋め込みだけ。
    private static func makeGatedImageFileReader(markdownURL: URL) -> InMemoryFileReader {
        let imageURL = markdownURL.deletingLastPathComponent().appendingPathComponent("gated.png")
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "unused"])
        fileReader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), at: imageURL)
        return fileReader
    }

    @Test("直接HTMLモード離脱の再ロード中にupdateContentが再発火しても最終的に描画される")
    func directHTMLExitSurvivesRaceDuringReload() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        await Self.waitForWebViewLoad { renderer.isReady }

        let fileA = URL(fileURLWithPath: "/tmp/task68-race-a.md")
        // 直接 HTML モードで fileA を表示中の状態を模す。
        renderer.isDirectHTMLMode = true
        renderer.lastDirectHTMLPath = fileA
        renderer.rendered.filePath = fileA
        renderer.rendered.isSourceMode = false

        // 1回目: 直接HTMLモードから離脱し、viewer.html の再ロードを開始する。
        renderer.updateContent(
            "# hello", contentRevision: 7, fileType: .markdown, filePath: fileA,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        #expect(renderer.isReady == false)

        // 2回目: 再ロード中に同じ対象で再発火し、単一スロットの pendingUpdate を上書きする
        // (FileWatcher の onChange や isLoading トグル等による再発火を模す)。
        renderer.updateContent(
            "# hello", contentRevision: 7, fileType: .markdown, filePath: fileA,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )

        // 再ロード完了前は、描画ミラーが「描画済み」だと先行確定していないことを確認する。
        #expect(renderer.rendered.contentRevision == nil)

        await Self.waitForWebViewLoad { renderer.isReady }
        // applyRender の画像埋め込み(Task.detached)は isReady 復帰後に別 Task で完了するため、
        // ミラー反映を待つ。
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision != nil }

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
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        await Self.waitForWebViewLoad { renderer.isReady }

        let dir = URL(fileURLWithPath: "/tmp/task334-diff")
        let imageURL = dir.appendingPathComponent("gated.png")
        let markdownURL = dir.appendingPathComponent("doc.md")
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "unused"])
        fileReader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), at: imageURL)
        let content = "![alt](gated.png)"
        let update = {
            renderer.updateContent(
                content, contentRevision: 1, fileType: .markdown, filePath: markdownURL,
                hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
                truncation: Self.truncation
            )
        }

        // 1 回目は素通しさせ、描画を完了させる（以降 contentRevision は変わらない）。
        let openGate = DispatchSemaphore(value: 1)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(base: fileReader, releaseGate: openGate, completed: LockedBox(false))
        )
        update()
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision == 1 }
        // 消費したカウントを戻す（減ったまま解放された DispatchSemaphore は
        // libdispatch のチェックに引っかかってプロセスごと落ちる）。
        openGate.signal()

        // 2 回目は差分が届いた状態で、埋め込みを閉じたゲートで止める
        // （埋め込みキャッシュを避けるため embedder ごと差し替える）。
        let gate = DispatchSemaphore(value: 0)
        let entered = LockedBox(false)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(
                base: fileReader, releaseGate: gate, completed: LockedBox(false), entered: entered
            )
        )
        let diff = ViewerRenderer.DiffState(
            text: "diff --git a/doc.md b/doc.md\n--- a/doc.md\n+++ b/doc.md\n@@ -1 +1 @@\n-old\n+new\n",
            layout: .inline
        )
        renderer.diffState = diff
        update()
        await Self.waitForWebViewLoad { entered.get() }

        // 中断中はまだ「反映済み」ではない（1 回目の描画で確定した .none のまま）。
        // ここで新しい差分を先行確定していると、次の更新が握り潰される。
        #expect(renderer.rendered.diffState == ViewerRenderer.DiffState.none)

        // 実機の updateNSView 再入を模した、同じ入力での再呼び出し。
        update()
        gate.signal()
        // 再入で握り潰されず、最終的に差分が反映される。
        await Self.waitForWebViewLoad { renderer.rendered.diffState == diff }
    }

    /// 中断された applyRender は、表示オプションを JS へ送ってはならない。送ってから
    /// 世代ガードで抜けるとミラーへ確定されず、以後の applyRender が「ミラーと同値」と
    /// 見て再送をスキップするため、JS 側に中断時の値が残り続ける(TASK-336)。
    ///
    /// 描画中に差分表示を ON→OFF した状況を作り、JS が保持する差分を直接読んで測る。
    /// ミラーだけを見ると「.none のまま」で両実装が同じに見えるため、判定は JS 側に置く。
    @Test("中断された描画は表示オプションを JS へ送り残さない")
    func abortedRenderDoesNotLeaveOptionsInJS() async throws {
        let renderer = ViewerRenderer()
        let webView = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        await Self.waitForWebViewLoad { renderer.isReady }

        let markdownURL = URL(fileURLWithPath: "/tmp/task336-abort/doc.md")
        let fileReader = Self.makeGatedImageFileReader(markdownURL: markdownURL)
        let content = "![alt](gated.png)"
        let update = {
            renderer.updateContent(
                content, contentRevision: 1, fileType: .markdown, filePath: markdownURL,
                hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false,
                truncation: Self.truncation
            )
        }

        // 1 回目は素通しさせ、差分なしの状態で描画を完了させる。
        let openGate = DispatchSemaphore(value: 1)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(base: fileReader, releaseGate: openGate, completed: LockedBox(false))
        )
        update()
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision == 1 }
        openGate.signal()

        // 2 回目: 差分 ON で描画を始め、画像埋め込みのゲートで中断させる。
        let gate = DispatchSemaphore(value: 0)
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
        gate.signal()
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

    @Test("画像埋め込みが遅延した古いupdateContentの結果は新しい呼び出しを上書きしない")
    func staleImageEmbedDoesNotClobberNewerRender() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        await Self.waitForWebViewLoad { renderer.isReady }

        let dir = URL(fileURLWithPath: "/tmp/task224-race")
        let imageURL = dir.appendingPathComponent("slow.png")
        let markdownURL = dir.appendingPathComponent("doc.md")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "unused"])
        fileReader.setDataFile(pngData, at: imageURL)
        // readData をゲートで足止めし、遅延埋め込みの完了タイミングをテストから明示的に制御する。
        let releaseGate = DispatchSemaphore(value: 0)
        let embedCompleted = LockedBox(false)
        renderer.imageEmbedder = MarkdownImageEmbedder(
            fileReader: SlowFileReader(base: fileReader, releaseGate: releaseGate, completed: embedCompleted)
        )

        // 1回目: 画像参照ありの content。埋め込みが releaseGate 解放まで完了しない。
        renderer.updateContent(
            "![alt](slow.png)", contentRevision: 1, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        // 2回目: 画像参照なしの content。埋め込みが不要で 1回目より先に rendered を更新する。
        renderer.updateContent(
            "no image here", contentRevision: 2, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )

        // 2回目(遅延なし)が先に完了するのを待つ。
        await Self.waitForWebViewLoad { renderer.rendered.contentRevision != nil }
        #expect(renderer.rendered.contentRevision == 2)

        // 1回目の遅延埋め込みを明示的に完了させ、完了後も上書きされていないことを確認する。
        releaseGate.signal()
        await Self.waitForWebViewLoad { embedCompleted.get() }
        // embedLocalImages 完了から rendered への反映判定まではさらに 1 Task 分の
        // 非同期遷移があるため、MainActor を数回 yield させてから確定させる。
        await yieldMainActor()
        #expect(renderer.rendered.contentRevision == 2)
    }

    @Test("makeWebView がコードフォント設定をロード前スクリプトへ注入する")
    func makeWebViewInjectsCodeFontScripts() {
        let renderer = ViewerRenderer()
        let webView = renderer.makeWebView(
            initialZoom: 1.0, findOptionsPreference: nil,
            codeFontFamily: "Menlo", codeFontSizePoints: 14
        )

        let sources = webView.configuration.userContentController.userScripts.map(\.source)

        #expect(sources.contains { $0.contains("_mmdMonoFontFamily") && $0.contains("Menlo") })
        #expect(sources.contains { $0.contains("_mmdCodeFontSize") && $0.contains("14") })
    }
}

/// readData を意図的に足止めし、embedLocalImages(Task.detached 内)の完了タイミングを
/// テストから制御するためのフェイク。他のメソッドは base にそのまま委譲する。
private struct SlowFileReader: FileReading {
    let base: InMemoryFileReader
    let releaseGate: DispatchSemaphore
    let completed: LockedBox<Bool>

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

    /// readData へ入った（＝呼び出し元が埋め込みで中断した）ことをテストへ知らせる。
    var entered: LockedBox<Bool>?

    func readData(from url: URL) throws -> Data {
        entered?.set(true)
        waitOrRecordTimeout(releaseGate, "SlowFileReader.readData")
        let data = try base.readData(from: url)
        completed.set(true)
        return data
    }
}
