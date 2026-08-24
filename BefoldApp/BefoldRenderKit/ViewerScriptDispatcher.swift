import BefoldKit
import os
import WebKit

/// 描画のために viewer.js へスクリプトを発行する経路。
///
/// 「送るのは変わったときだけ」「送信とミラー確定を同じ同期区間へ」という 2 つの制約が
/// 効くのはこの型の中だけなので、evaluateJavaScript の発行点をここへ集めてある。
@MainActor
final class ViewerScriptDispatcher {
    private unowned let renderer: ViewerRenderer

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    /// JS 評価の失敗を残す口（TASK-548）。
    ///
    /// これまで描画スクリプトは `completionHandler: nil` で投げっぱなしにしており、
    /// JS 側で例外が出ても Swift 側は成功と区別できなかった（本文が空白のまま返らない
    /// 不具合が「開くのが遅い」としか見えなかったのはこのため）。ここを通せば
    /// `log stream --predicate 'subsystem == "com.degino.befold"'` で拾える。
    ///
    /// なお JS が**返らない**（無限ループ・破滅的バックトラック）場合は completionHandler
    /// 自体が呼ばれないので、ここでは検出できない。その形は
    /// scripts/webview-smoke.swift の所要時間アサートが受け持つ。
    private static let log = Logger(subsystem: "com.degino.befold", category: "viewer-script")

    /// evaluateJavaScript の共通口。失敗したスクリプトの用途（label）とエラーを残す。
    /// この型からの評価は必ずここを通すこと（nil の completionHandler を直接渡さない）。
    private func evaluate(_ script: String, on webView: WKWebView, label: String) {
        webView.evaluateJavaScript(script) { _, error in
            guard let error else { return }
            Self.log
                .error(
                    "viewer script failed (\(label, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    /// content の埋め込み加工(markdown ローカル画像の data URI 差し替え)を MainActor 外へ逃がす。
    /// MarkdownImageEmbedder は Sendable かつ内部キャッシュが NSLock 保護のため並行呼び出し可。
    private func embeddedContent(
        _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool
    ) async -> String {
        let embedImages = renderer.rendererFeatures.embedImages
        let embedder = renderer.imageEmbedder
        return await withBlockingWork(qos: .userInitiated) {
            RenderableContent.make(
                content, fileType: fileType, filePath: filePath,
                isSourceMode: isSourceMode, embedImages: embedImages, imageEmbedder: embedder
            )
        }
    }

    /// pendingAppend を消費して次チャンクを増分追記する(全文 render しない)。
    /// truncation は updateContent が受け取った現在値をそのまま使う。
    /// chunk が空(チャンク読込エラーのセンチネル)の場合は追記せず、切り詰めバナーだけ更新する。
    /// 画像埋め込み(embeddedContent)は MainActor 外で行うため、完了後に
    /// contentUpdateGeneration が呼び出し時から変わっていないか確認してから
    /// evaluateJavaScript/recordRendered を行う(後続の updateContent に追い越された場合は破棄)。
    func applyAppend(webView: WKWebView, request: AppendRequest) async {
        // 追記チャンクも初回描画と同じ加工を通す。markdown をチャンク読み込みの
        // 対象にしたため(Issue #307)、ここを素通しすると 2 チャンク目以降の
        // ローカル画像だけが data URI に差し替わらず画像割れになる。
        let renderable = await embeddedContent(
            request.chunk, fileType: request.fileType,
            filePath: request.filePath, isSourceMode: request.isSourceMode
        )
        guard request.generation == renderer.contentUpdateGeneration else { return }

        // 送信と recordRendered は同じ同期区間に閉じ込める(applyRender と同じ理由)。
        // ガードより前で送ると、追い越された呼び出しが「JS へは送ったのにミラーは旧値の
        // まま」を残し、次の truncation が旧値と一致したとき再送が飛ぶ(TASK-336・417)。
        evaluate(request.truncation.script, on: webView, label: "truncation(append)")
        if !renderable.isEmpty,
           let script = ViewerBridge.appendChunkScript(chunk: renderable, fileType: request.fileType)
        {
            evaluate(script, on: webView, label: "appendChunk")
        }
        var state = renderer.rendered
        state.contentRevision = request.contentRevision
        state.fileType = request.fileType
        state.filePath = request.filePath
        state.truncation = request.truncation
        renderer.recordRendered(state)
    }

    /// 描画済みミラーとの差分を見て lineNumbers / viewMode / 差分 / 切り詰めを同期し、
    /// scrollKey 予告 + render を評価する。
    ///
    /// 画像埋め込み(embeddedContent)は MainActor 外で行うため、完了後に
    /// contentUpdateGeneration が呼び出し時から変わっていないか確認してから
    /// evaluateJavaScript/recordRendered を行う(後続の updateContent に追い越された場合は破棄)。
    /// **表示オプションの送信・render の評価・recordRendered はこの世代ガードより後ろに
    /// 一続きで並べ、間に await を挟まないこと**(理由は本文中のコメント)。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    func applyRender(
        webView: WKWebView, request: RenderRequest, restoreFromPersistedPosition: Bool
    ) async {
        let renderable = await embeddedContent(
            request.content, fileType: request.fileType,
            filePath: request.filePath, isSourceMode: request.isSourceMode
        )
        guard request.generation == renderer.contentUpdateGeneration else { return }
        guard let script = ViewerBridge.renderScript(content: renderable, fileType: request.fileType)
        else { return }

        // 表示オプションの送信・render の評価・ミラーへの確定を、await を挟まずここへ並べる。
        // 「送るのは変わったときだけ」なので、送信とミラー確定の間に suspension point を置くと
        // 中断された呼び出しが「送ったが記録していない」状態を残し、以後の呼び出しが
        // ミラーと同値と見て再送をスキップして JS 側に中断時の値が残る(TASK-336)。
        // 逆に送信前へ確定を移すと、await 中に再入した updateContent が
        // incoming == rendered と判定して描画を握り潰す(TASK-334)。両方を避けられるのは、
        // 送信と確定を同じ同期区間に閉じ込めるこの位置だけ。
        let sentDiffState = renderer.diffState
        sendDisplayOptions(webView: webView, request: request, diffState: sentDiffState)
        // 次の render が表示する文書パスの予告。JS は render 開始時に採用し、以後の
        // スクロール通知の保存キー(payload の path)として位置と同じターンで読んで返す。
        // 切替以外の再描画でも毎回送る(viewer.html 再ロードで JS 状態が飛んでも
        // 次の render で自己修復させるため)。
        evaluate(
            ViewerBridge.renderDocPathScript(request.filePath), on: webView, label: "renderDocPath"
        )
        if restoreFromPersistedPosition {
            evaluate(
                ViewerBridge.restoreScrollPositionScript(renderer.scrollPositionToRestore),
                on: webView, label: "restoreScrollPosition"
            )
        }
        evaluate(script, on: webView, label: "render")
        renderer.recordRendered(
            RenderedStateMirror(
                contentRevision: request.contentRevision, fileType: request.fileType,
                filePath: request.filePath, showLineNumbers: request.showLineNumbers,
                isSourceMode: request.isSourceMode, truncation: request.truncation,
                diffState: sentDiffState
            )
        )
    }

    /// 描画済みミラーと違うものだけを送る。呼び出し元と同じ同期区間で実行すること。
    private func sendDisplayOptions(
        webView: WKWebView, request: RenderRequest, diffState: DiffState
    ) {
        let rendered = renderer.rendered
        if request.showLineNumbers != rendered.showLineNumbers {
            evaluate(
                ViewerBridge.lineNumbersScript(request.showLineNumbers), on: webView,
                label: "lineNumbers"
            )
        }
        if request.isSourceMode != rendered.isSourceMode {
            evaluate(
                ViewerBridge.viewModeScript(.init(isSourceMode: request.isSourceMode)),
                on: webView, label: "viewMode"
            )
        }
        // 差分は本文とレイアウトを 1 つの値として比較し、変わったときだけ両方送る。
        // 直後の render で JS 側が読み出すため、ここでは送るだけ(再描画はしない)。
        if diffState != rendered.diffState {
            evaluate(ViewerDiffBridge.textScript(diffState.text), on: webView, label: "diffText")
            evaluate(ViewerDiffBridge.layoutScript(diffState.layout), on: webView, label: "diffLayout")
        }
        if request.truncation != rendered.truncation {
            evaluate(request.truncation.script, on: webView, label: "truncation")
        }
    }
}
