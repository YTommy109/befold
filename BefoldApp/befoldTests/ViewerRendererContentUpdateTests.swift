import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// updateContent の純粋なミラー更新判定を検証する。同一 revision でも filePath が
/// 変われば再描画対象と判定すること、pendingAppend 消費可否の判定(canConsumePendingAppend)
/// が対象を扱う。実 WKWebView をロードして描画完了まで待つテストは
/// ViewerRendererContentUpdateIntegrationTests へ分離した。
@Suite(testTimeLimit())
struct ViewerRendererContentUpdateTests {
    private static let truncation = ViewerRenderer.TruncationState(isTruncated: false, lineCount: 0, failed: false)

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
        await waitUntilYielding { renderer.rendered.filePath == fileB }

        #expect(renderer.rendered.filePath == fileB)
    }

    // MARK: - pendingAppend 消費判定(showLineNumbers 不一致は全文 render に倒す)

    // pendingAppend 消費経路のガードが showLineNumbers を見ておらず、
    // 同一 revision の pending append と行番号トグルが1つの @Observable サイクルに合体すると
    // トグルが1周期失われうる問題への回帰テスト。

    @Test("revision・ファイル・showLineNumbers の一致/不一致で増分追記の可否が決まる", arguments: [
        // (直近描画の showLineNumbers, pending の revision, チェック側の revision・ファイル, 期待値)
        (renderedShowLineNumbers: true, pendingRevision: 5, checkRevision: 5, checkFile: "a.md", expected: true),
        // showLineNumbers が直近描画から変化(revision と pending append の合体)していれば全文 render に倒す
        (false, 5, 5, "a.md", false),
        (true, 4, 5, "a.md", false), // revision が不一致なら全文 render に倒す
        (true, 5, 5, "b.md", false), // ファイル切替を伴うなら全文 render に倒す
    ])
    func canConsumePendingAppend(
        renderedShowLineNumbers: Bool, pendingRevision: Int, checkRevision: Int,
        checkFile: String, expected: Bool
    ) {
        let renderedURL = URL(fileURLWithPath: "/tmp/a.md")
        var rendered = ViewerRenderer.RenderedStateMirror()
        rendered.filePath = renderedURL
        rendered.isSourceMode = false
        rendered.showLineNumbers = renderedShowLineNumbers
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: pendingRevision)

        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending,
            ViewerRenderer.PendingAppendCheck(
                contentRevision: checkRevision, showLineNumbers: true,
                filePath: URL(fileURLWithPath: "/tmp/\(checkFile)"), isSourceMode: false
            ),
            rendered: rendered
        )

        #expect(canConsume == expected)
    }
}
