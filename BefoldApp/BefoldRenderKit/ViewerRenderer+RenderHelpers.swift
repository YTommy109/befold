import BefoldKit
import WebKit

// MARK: - Render helpers

extension ViewerRenderer {
    /// 次チャンクを非同期で取得し、次チャンクを pendingAppend にステージする。
    /// 実際の増分描画はここでは行わず、@Observable(content/contentRevision/truncation)の
    /// 変更が駆動する updateContent(唯一の描画 sink)が pendingAppend を消費して行う。
    /// これにより「追記の描画」経路が updateContent 1 本に一本化される。
    /// 読み込み中の再入は isLoadingMoreLines で無視し、追記の交錯を防ぐ。
    @MainActor
    func handleLoadMoreLines() {
        guard !isLoadingMoreLines else { return }
        isLoadingMoreLines = true
        Task { @MainActor [self] in
            defer { isLoadingMoreLines = false }
            guard let result = await delegate?.rendererDidRequestMoreLines(self) else { return }
            // updateContent が消費する前に次の続き読み込みが完了した場合(SwiftUI 更新の
            // 合体)に備え、未消費チャンクへ連結する。上書きすると先行チャンクが DOM へ
            // 追記されないまま失われるため、必ず累積する。revision は最新値を採る。
            let combinedChunk = (pendingAppend?.chunk ?? "") + result.chunk
            pendingAppend = PendingAppend(chunk: combinedChunk, revision: result.contentRevision)
        }
    }

    /// content の埋め込み加工(markdown ローカル画像の data URI 差し替え)を MainActor 外へ逃がす。
    /// MarkdownImageEmbedder は Sendable かつ内部キャッシュが NSLock 保護のため並行呼び出し可。
    func embeddedContent(
        _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool
    ) async -> String {
        let embedImages = rendererFeatures.embedImages
        let embedder = imageEmbedder
        return await Task.detached(priority: .userInitiated) {
            Self.renderableContent(
                content, fileType: fileType, filePath: filePath,
                isSourceMode: isSourceMode, embedImages: embedImages, imageEmbedder: embedder
            )
        }.value
    }

    /// pendingAppend を消費して次チャンクを増分追記する(全文 render しない)。
    /// truncation は updateContent が受け取った現在値をそのまま使う。
    /// chunk が空(チャンク読込エラーのセンチネル)の場合は追記せず、切り詰めバナーだけ更新する。
    /// 画像埋め込み(embeddedContent)は MainActor 外で行うため、完了後に
    /// contentUpdateGeneration が呼び出し時から変わっていないか確認してから
    /// evaluateJavaScript/recordRendered を行う(後続の updateContent に追い越された場合は破棄)。
    func applyAppend(webView: WKWebView, request: AppendRequest) async {
        let (chunk, contentRevision, fileType, filePath, isSourceMode, truncation, generation) = (
            request.chunk, request.contentRevision, request.fileType, request.filePath,
            request.isSourceMode, request.truncation, request.generation
        )
        // applyRender と同じ理由で、送るのは今・ミラーへの確定は追記を評価した後
        // （await 中に再入した updateContent へ「反映済み」と誤って見せない）。
        webView.evaluateJavaScript(
            truncation.script,
            completionHandler: nil
        )

        // 追記チャンクも初回描画と同じ加工を通す。markdown をチャンク読み込みの
        // 対象にしたため(Issue #307)、ここを素通しすると 2 チャンク目以降の
        // ローカル画像だけが data URI に差し替わらず画像割れになる。
        let renderable = await embeddedContent(
            chunk, fileType: fileType, filePath: filePath, isSourceMode: isSourceMode
        )
        guard generation == contentUpdateGeneration else { return }

        if !renderable.isEmpty,
           let script = ViewerBridge.appendChunkScript(chunk: renderable, fileType: fileType)
        {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        var state = rendered
        state.contentRevision = contentRevision
        state.fileType = fileType
        state.filePath = filePath
        state.truncation = truncation
        recordRendered(state)
    }

    /// last* キャッシュとの差分を見て lineNumbers / viewMode / 差分 / 切り詰めを同期し、
    /// scrollKey 予告 + render を評価する。
    ///
    /// 画像埋め込み(embeddedContent)は MainActor 外で行うため、完了後に
    /// contentUpdateGeneration が呼び出し時から変わっていないか確認してから
    /// evaluateJavaScript/recordRendered を行う(後続の updateContent に追い越された場合は破棄)。
    /// **表示オプションの送信・render の評価・recordRendered はこの世代ガードより後ろに
    /// 一続きで並べ、間に await を挟まないこと**(理由は本文中のコメント)。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    func applyRender(
        webView: WKWebView, request: RenderRequest,
        restoreFromPersistedPosition: Bool
    ) async {
        let (content, contentRevision, fileType, filePath, isSourceMode, showLineNumbers, truncation, generation) = (
            request.content, request.contentRevision, request.fileType, request.filePath,
            request.isSourceMode, request.showLineNumbers, request.truncation, request.generation
        )
        let renderable = await embeddedContent(
            content, fileType: fileType, filePath: filePath, isSourceMode: isSourceMode
        )
        guard generation == contentUpdateGeneration else { return }

        guard let script = ViewerBridge.renderScript(content: renderable, fileType: fileType) else { return }

        // 表示オプションの送信・render の評価・ミラーへの確定を、await を挟まずここへ並べる。
        // 「送るのは変わったときだけ」なので、送信とミラー確定の間に suspension point を置くと
        // 中断された呼び出しが「送ったが記録していない」状態を残し、以後の呼び出しが
        // ミラーと同値と見て再送をスキップして JS 側に中断時の値が残る(TASK-336)。
        // 逆に送信前へ確定を移すと、await 中に再入した updateContent が
        // incoming == rendered と判定して描画を握り潰す(TASK-334)。両方を避けられるのは、
        // 送信と確定を同じ同期区間に閉じ込めるこの位置だけ。
        let sentDiffState = diffState
        if showLineNumbers != rendered.showLineNumbers {
            webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers), completionHandler: nil)
        }
        if isSourceMode != rendered.isSourceMode {
            webView.evaluateJavaScript(
                ViewerBridge.viewModeScript(.init(isSourceMode: isSourceMode)), completionHandler: nil
            )
        }
        // 差分は本文とレイアウトを 1 つの値として比較し、変わったときだけ両方送る。
        // 直後の render で JS 側が読み出すため、ここでは送るだけ(再描画はしない)。
        if sentDiffState != rendered.diffState {
            webView.evaluateJavaScript(ViewerBridge.diffScript(sentDiffState.text), completionHandler: nil)
            webView.evaluateJavaScript(
                ViewerBridge.diffLayoutScript(sentDiffState.layout), completionHandler: nil
            )
        }
        if truncation != rendered.truncation {
            webView.evaluateJavaScript(
                truncation.script,
                completionHandler: nil
            )
        }
        // 次の render が表示する文書パスの予告。JS は render 開始時に採用し、以後の
        // スクロール通知の保存キー(payload の path)として位置と同じターンで読んで返す。
        // 切替以外の再描画でも毎回送る(viewer.html 再ロードで JS 状態が飛んでも
        // 次の render で自己修復させるため)。
        webView.evaluateJavaScript(ViewerBridge.renderDocPathScript(filePath), completionHandler: nil)
        if restoreFromPersistedPosition {
            webView.evaluateJavaScript(
                ViewerBridge.restoreScrollPositionScript(scrollPositionToRestore), completionHandler: nil
            )
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
        recordRendered(
            RenderedStateMirror(
                contentRevision: contentRevision, fileType: fileType, filePath: filePath,
                showLineNumbers: showLineNumbers, isSourceMode: isSourceMode,
                truncation: truncation, diffState: sentDiffState
            )
        )
    }

    /// 描画済みキャッシュをまるごと確定させる。render()/append() を実際に
    /// evaluateJavaScript した後にだけ呼ぶこと（`applyRender` の解説を参照）。
    /// content 全文は保持せず contentRevision だけを比較用に保存する。
    ///
    /// 確定の入口はこの 1 つだけにしてある。フィールドを部分更新できる入口を残すと、
    /// ミラーへフィールドを足したときにそこだけ確定漏れが起き、状態変化が 1 周期
    /// 失われる(TASK-320 / TASK-334 で 2 度起きた形)。一部のフィールドだけを
    /// 変えたい呼び出し元は、現在の `rendered` を複製して書き換えてから渡すこと。
    func recordRendered(_ state: RenderedStateMirror) {
        rendered = state
    }

    /// ファイルの rename / move を描画状態へ追随させる。DOM は同一文書のまま名前だけが
    /// 変わるため、再描画はせず「描画済みミラーの filePath」と「JS 側の文書パス」を
    /// 同じ同期区間で差し替える。
    ///
    /// - ミラーが新パスを指すことで、後続の再ロードは同一ファイルの再描画になり
    ///   (`isFileOrModeSwitch` が false)、保存済みスクロール位置は注入されない。
    ///   viewer.js は render 直前の scrollTop を fallback に使うため現在位置がそのまま保たれる
    ///   (提示開始時の保存値へ巻き戻さない = TASK-401)。
    /// - JS 側の文書パスも即時に差し替えるため、リネーム再描画の確定前に発火した
    ///   スクロール通知も新パスをキーに保存される(旧パスのキーは
    ///   `perFileState.migrate` 済みで、もう読まれない = TASK-393)。
    ///
    /// 描画済みの文書が oldURL と別(未描画・別文書へ切替中)の場合は何もしない。
    public func handleRename(from oldURL: URL, to newURL: URL) {
        guard rendered.filePath?.normalizedPathKey == oldURL.normalizedPathKey else { return }
        var state = rendered
        state.filePath = newURL
        recordRendered(state)
        webView?.evaluateJavaScript(
            ViewerBridge.renameDocPathScript(from: oldURL, to: newURL), completionHandler: nil
        )
    }

    /// pendingAppend(段階読み込みでステージされた次チャンク)を全文 render せず増分描画して
    /// よいかどうかを判定する。
    ///
    /// 追記経路が JS へ送るのはチャンクと切り詰め状態だけで、行番号・モード・差分などの
    /// 注入は行わない。よって「追記が正しく更新できる 2 つ(contentRevision と truncation)を
    /// 除いて、更新後の状態が描画済みと一致している」ときだけ消費してよい。
    ///
    /// 比較する条件を並べず、ミラー同士を丸ごと突き合わせる形にしているのは、
    /// 列挙にするとミラーへフィールドを足したときにここへの追加だけ漏れ、その状態変化が
    /// 追記経路に吸収されて 1 周期失われるため(行番号トグルで一度、差分トグルで
    /// もう一度起きた形 = TASK-320)。
    nonisolated static func canConsumePendingAppend(
        _ pending: PendingAppend, incoming: RenderedStateMirror, rendered: RenderedStateMirror
    ) -> Bool {
        guard pending.revision == incoming.contentRevision else { return false }
        var comparable = incoming
        comparable.contentRevision = rendered.contentRevision
        comparable.truncation = rendered.truncation
        return comparable == rendered
    }

    /// 呼び出し前に `exitDirectHTMLMode` が `rendered.reset()` でミラーを一括破棄済みである
    /// 前提。再ロードで viewer.html の JS 状態(_mmdViewOptions: 行番号 false, モード rendered)が
    /// 初期化されるのに合わせ、次回更新時に setLineNumbers / setViewMode を再注入させる。
    func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
        isReady = false
        // 読み直すと JS 側の状態(参照解決の FIFO キューを含む)が捨てられる。飛行中の
        // 応答を新しいページへ適用しないよう世代を進める(TASK-421)。
        pageGeneration += 1
        // atDocumentStart の initialZoomScript はウィンドウ生成時の倍率で焼き付いているため、
        // 直接ロードから復帰した viewer.html に切替後の現在ファイルの保存倍率を適用し直す。
        let zoom = initialPageZoom
        pendingUpdate = {
            webView.evaluateJavaScript(ViewerBridge.applyZoomScript(zoom))
            completion()
        }
        // viewer.html（mermaid.js）は JS 必須のため、直接ロードで無効化した JS を再有効化する。
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        ViewerRenderer.loadViewerHTML(into: webView)
    }
}

public extension ViewerRenderer {
    /// 直接 HTML モード(loadFileURL による親ディレクトリ read)へ入るべきかどうかを判定する。
    /// features.allowDirectHTML が false の場合は常に入らず、viewer.html 経由の通常描画に
    /// フォールバックする(QuickLook 等、親ディレクトリへの read 権限がない実行環境向け)。
    nonisolated static func shouldEnterDirectHTMLMode(
        fileType: FileType, isSourceMode: Bool, filePath: URL?, features: RendererFeatures
    ) -> Bool {
        fileType == .html && !isSourceMode && filePath != nil && features.allowDirectHTML
    }

    /// 今回の render() がファイル/モードの実際の切替かどうかを判定する。
    /// 切替時のみ永続化済みスクロール位置(最大 200ms 古い可能性がある)で復元し、
    /// 同一ファイル・同一モードでの再描画(ライブリロード・行番号トグル等)では
    /// ライブの現在スクロール位置を優先させる(JS 側フォールバック。applyRender 参照)。
    nonisolated static func isFileOrModeSwitch(
        filePath: URL?, isSourceMode: Bool,
        lastRenderedFilePath: URL?, lastIsSourceMode: Bool?
    ) -> Bool {
        filePath != lastRenderedFilePath || isSourceMode != lastIsSourceMode
    }

    /// render() に渡す直前のコンテンツ加工。markdown はローカル画像参照を
    /// data URI に差し替える(相対パスの解決基準として filePath が必要)。
    /// ソース表示中は原文をそのまま見せるため、埋め込みは行わない。
    nonisolated static func renderableContent(
        _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool,
        embedImages: Bool = true,
        imageEmbedder: MarkdownImageEmbedder = .shared
    ) -> String {
        guard !isSourceMode, fileType == .markdown, let filePath, embedImages else { return content }
        // ロード時のウォームアップと同じキャッシュを引くため、同一インスタンス(本番は .shared)を経由すること。
        return imageEmbedder.embedLocalImages(in: content, baseURL: filePath)
    }
}
