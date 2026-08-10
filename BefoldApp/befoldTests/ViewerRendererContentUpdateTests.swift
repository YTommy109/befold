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

    // MARK: - pendingAppend 消費判定(追記で更新できない差があれば全文 render に倒す)

    // 追記経路はチャンクと切り詰め状態しか送らないため、それ以外の状態が同一サイクルで
    // 変わったのに追記へ吸収されると、その変化が 1 周期失われる。行番号トグルで一度
    // (TASK-68)、差分トグルでもう一度(TASK-320)起きた形の回帰テスト。

    /// 直近描画の状態。各ケースはここから 1 点だけ動かした「更新後」を作る。
    private static func renderedMirror() -> ViewerRenderer.RenderedStateMirror {
        ViewerRenderer.RenderedStateMirror(
            contentRevision: 5, fileType: .markdown, filePath: URL(fileURLWithPath: "/tmp/a.md"),
            showLineNumbers: true, isSourceMode: false,
            truncation: ViewerRenderer.TruncationState(isTruncated: true, lineCount: 100, failed: false),
            diffState: ViewerRenderer.DiffState.none
        )
    }

    struct AppendCase: Sendable, CustomTestStringConvertible {
        let label: String
        let pendingRevision: Int
        /// 直近描画から動かす 1 点。
        let mutate: @Sendable (inout ViewerRenderer.RenderedStateMirror) -> Void
        let expected: Bool
        var testDescription: String {
            label
        }
    }

    private static let appendCases: [AppendCase] = [
        AppendCase(label: "追記だけの差(世代と切り詰め)なら増分追記できる", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.truncation = ViewerRenderer.TruncationState(isTruncated: true, lineCount: 200, failed: false)
        }, expected: true),
        AppendCase(label: "pending の世代が更新後と食い違えば全文 render", pendingRevision: 4, mutate: {
            $0.contentRevision = 6
        }, expected: false),
        AppendCase(label: "行番号トグルが同じサイクルに合体したら全文 render", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.showLineNumbers = false
        }, expected: false),
        // 追記経路は setDiff / setDiffLayout を送らないため、差分の変化を吸収させてはいけない。
        AppendCase(label: "差分トグルが同じサイクルに合体したら全文 render", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.diffState = ViewerRenderer.DiffState(text: "@@ -1 +1 @@", layout: .inline)
        }, expected: false),
        AppendCase(label: "差分レイアウトの変更も全文 render", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.diffState = ViewerRenderer.DiffState(text: nil, layout: .sideBySide)
        }, expected: false),
        AppendCase(label: "ファイル切替を伴うなら全文 render", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.filePath = URL(fileURLWithPath: "/tmp/b.md")
        }, expected: false),
        AppendCase(label: "ソース表示への切替を伴うなら全文 render", pendingRevision: 6, mutate: {
            $0.contentRevision = 6
            $0.isSourceMode = true
        }, expected: false),
    ]

    @Test("追記で更新できる差だけのときに増分追記できる", arguments: appendCases)
    func canConsumePendingAppend(testCase: AppendCase) {
        let rendered = Self.renderedMirror()
        var incoming = rendered
        testCase.mutate(&incoming)
        let pending = ViewerRenderer.PendingAppend(chunk: "next", revision: testCase.pendingRevision)

        let canConsume = ViewerRenderer.canConsumePendingAppend(
            pending, incoming: incoming, rendered: rendered
        )

        #expect(canConsume == testCase.expected)
    }

    // MARK: - rename の追随(handleRename)

    /// リネームは再描画せず、描画済みミラーの filePath だけを新パスへ差し替える。
    /// 差し替えないと、リネーム再ロードがファイル切替として扱われて保存済み
    /// スクロール位置が注入され、現在位置が提示開始時の値へ巻き戻る(TASK-401)。
    @Test("handleRename は描画済みミラーの filePath を差し替え、他のミラー値を保つ")
    @MainActor
    func handleRenameRetargetsMirrorFilePath() {
        let renderer = ViewerRenderer()
        let oldURL = URL(fileURLWithPath: "/tmp/before.md")
        let newURL = URL(fileURLWithPath: "/tmp/after.md")
        renderer.rendered.filePath = oldURL
        renderer.rendered.contentRevision = 7
        renderer.rendered.isSourceMode = true

        renderer.handleRename(from: oldURL, to: newURL)

        #expect(renderer.rendered.filePath == newURL)
        #expect(renderer.rendered.contentRevision == 7)
        #expect(renderer.rendered.isSourceMode == true)
    }

    @Test("handleRename は描画済みの文書が一致しないとき何もしない", arguments: [
        // 未描画(filePath nil)と、別文書を描画済みの 2 通り
        nil, "/tmp/unrelated.md",
    ])
    @MainActor
    func handleRenameIgnoresMismatchedMirror(renderedPath: String?) {
        let renderer = ViewerRenderer()
        let mirrorURL = renderedPath.map { URL(fileURLWithPath: $0) }
        renderer.rendered.filePath = mirrorURL

        renderer.handleRename(
            from: URL(fileURLWithPath: "/tmp/before.md"), to: URL(fileURLWithPath: "/tmp/after.md")
        )

        #expect(renderer.rendered.filePath == mirrorURL)
    }
}
