import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// 直接 HTML モード離脱時の再ロード中に updateContent が再発火して
/// pendingUpdate(単一スロット)が上書きされても、最終的に正しく描画されることを検証する
/// 回帰テスト。recordRendered が実描画(render スクリプト評価)後にのみ呼ばれる構造であれば、
/// 上書きで離脱時の描画が失われても描画ミラーが「未描画」のまま残り、次の updateContent が
/// 自然に再描画で回復する。
@Suite
struct ViewerRendererContentUpdateTests {
    private static let truncation = ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false)

    @Test("直接HTMLモード離脱の再ロード中にupdateContentが再発火しても最終的に描画される")
    @MainActor
    func directHTMLExitSurvivesRaceDuringReload() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        while !renderer.isReady {
            await Task.yield()
        }

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

        while !renderer.isReady {
            await Task.yield()
        }
        // applyRender の画像埋め込み(Task.detached)は isReady 復帰後に別 Task で完了するため、
        // ミラー反映を待つ。
        while renderer.rendered.contentRevision == nil {
            await Task.yield()
        }

        // 再ロード完了後、上書きされて残った2回目の更新が実描画され、ミラーが正しく更新される。
        #expect(renderer.rendered.contentRevision == 7)
        #expect(renderer.rendered.filePath == fileA)
    }

    @Test("同一revisionでもfilePathが変われば新ファイル基準で再描画される")
    @MainActor
    func needsRenderDetectsFilePathChangeEvenWithSameRevision() async {
        let renderer = ViewerRenderer()
        renderer.webView = WKWebView()
        renderer.isReady = true

        let fileA = URL(fileURLWithPath: "/tmp/task68-same-a.md")
        let fileB = URL(fileURLWithPath: "/tmp/task68-same-b.md")

        // fileA を revision 3 で描画済みの状態を模す。
        renderer.rendered.contentRevision = 3
        renderer.rendered.fileType = .markdown
        renderer.rendered.filePath = fileA
        renderer.rendered.showLineNumbers = false
        renderer.rendered.isSourceMode = false
        renderer.rendered.truncation = Self.truncation

        // 内容バイト列が同一で dataHash が一致する fileB へ切替える
        // (revision が fileA と同じ 3 のまま据え置かれるケースを模す)。
        renderer.updateContent(
            "# same content", contentRevision: 3, fileType: .markdown, filePath: fileB,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        // applyRender の画像埋め込み(Task.detached)は別 Task で完了するため、ミラー反映を待つ。
        while renderer.rendered.filePath != fileB {
            await Task.yield()
        }

        #expect(renderer.rendered.filePath == fileB)
    }

    @Test("画像埋め込みが遅延した古いupdateContentの結果は新しい呼び出しを上書きしない")
    @MainActor
    func staleImageEmbedDoesNotClobberNewerRender() async {
        let renderer = ViewerRenderer()
        _ = renderer.makeWebView(initialZoom: 1.0, findOptionsPreference: nil)
        while !renderer.isReady {
            await Task.yield()
        }

        let dir = URL(fileURLWithPath: "/tmp/task224-race")
        let imageURL = dir.appendingPathComponent("slow.png")
        let markdownURL = dir.appendingPathComponent("doc.md")
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let fileReader = InMemoryFileReader(files: [markdownURL.path: "unused"])
        fileReader.setDataFile(pngData, at: imageURL)
        renderer.imageEmbedder = MarkdownImageEmbedder(fileReader: SlowFileReader(base: fileReader))

        // 1回目: 画像参照ありの content。埋め込みが SlowFileReader の遅延で完了が遅れる。
        renderer.updateContent(
            "![alt](slow.png)", contentRevision: 1, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )
        // 2回目: 画像参照なしの content。埋め込みが速く完了し、1回目より先に rendered を更新する。
        renderer.updateContent(
            "no image here", contentRevision: 2, fileType: .markdown, filePath: markdownURL,
            hasDeclaredHTMLCharset: nil, isSourceMode: false, showLineNumbers: false, truncation: Self.truncation
        )

        // 2回目(遅延なし)が先に完了するのを待つ。
        while renderer.rendered.contentRevision == nil {
            await Task.yield()
        }
        #expect(renderer.rendered.contentRevision == 2)

        // 1回目の遅延埋め込みが完了するまで十分待ってから、上書きされていないことを確認する。
        try? await Task.sleep(for: .milliseconds(500))
        #expect(renderer.rendered.contentRevision == 2)
    }

    // MARK: - pendingAppend 消費判定(showLineNumbers 不一致は全文 render に倒す)

    // pendingAppend 消費経路のガードが showLineNumbers を見ておらず、
    // 同一 revision の pending append と行番号トグルが1つの @Observable サイクルに合体すると
    // トグルが1周期失われうる問題への回帰テスト。

    @Test("revision・ファイル・showLineNumbers が全て一致すれば増分追記できる")
    func canConsumePendingAppendAllowsWhenEverythingMatches() {
        let url = URL(fileURLWithPath: "/tmp/a.md")
        var rendered = ViewerRenderer.RenderedStateMirror()
        rendered.filePath = url
        rendered.isSourceMode = false
        rendered.showLineNumbers = true
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: 5)

        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending,
            ViewerRenderer.PendingAppendCheck(
                contentRevision: 5, showLineNumbers: true, filePath: url, isSourceMode: false
            ),
            rendered: rendered
        )

        #expect(canConsume == true)
    }

    @Test("showLineNumbers が直近描画から変化していれば全文 render に倒す")
    func canConsumePendingAppendRejectsWhenShowLineNumbersChanged() {
        let url = URL(fileURLWithPath: "/tmp/a.md")
        var rendered = ViewerRenderer.RenderedStateMirror()
        rendered.filePath = url
        rendered.isSourceMode = false
        rendered.showLineNumbers = false
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: 5)

        // 同一 revision の pending append と行番号トグルが1サイクルに合体したケース。
        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending,
            ViewerRenderer.PendingAppendCheck(
                contentRevision: 5, showLineNumbers: true, filePath: url, isSourceMode: false
            ),
            rendered: rendered
        )

        #expect(canConsume == false)
    }

    @Test("revision が不一致なら全文 render に倒す")
    func canConsumePendingAppendRejectsWhenRevisionMismatches() {
        let url = URL(fileURLWithPath: "/tmp/a.md")
        var rendered = ViewerRenderer.RenderedStateMirror()
        rendered.filePath = url
        rendered.isSourceMode = false
        rendered.showLineNumbers = true
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: 4)

        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending,
            ViewerRenderer.PendingAppendCheck(
                contentRevision: 5, showLineNumbers: true, filePath: url, isSourceMode: false
            ),
            rendered: rendered
        )

        #expect(canConsume == false)
    }

    @Test("ファイル切替を伴うなら全文 render に倒す")
    func canConsumePendingAppendRejectsWhenFileSwitches() {
        var rendered = ViewerRenderer.RenderedStateMirror()
        rendered.filePath = URL(fileURLWithPath: "/tmp/a.md")
        rendered.isSourceMode = false
        rendered.showLineNumbers = true
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: 5)

        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending,
            ViewerRenderer.PendingAppendCheck(
                contentRevision: 5, showLineNumbers: true,
                filePath: URL(fileURLWithPath: "/tmp/b.md"), isSourceMode: false
            ),
            rendered: rendered
        )

        #expect(canConsume == false)
    }

    @Test("makeWebView がコードフォント設定をロード前スクリプトへ注入する")
    @MainActor
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

/// readData を意図的に遅延させ、embedLocalImages(Task.detached 内)の完了タイミングを
/// テストから制御するためのフェイク。他のメソッドは base にそのまま委譲する。
private struct SlowFileReader: FileReading {
    let base: InMemoryFileReader

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
        Thread.sleep(forTimeInterval: 0.1)
        return try base.readData(from: url)
    }
}
