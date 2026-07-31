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
        rendered.truncation = truncation
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
        recordRendered(contentRevision: contentRevision, fileType: fileType, filePath: filePath)
    }

    /// last* キャッシュとの差分を見て lineNumbers / viewMode を同期し、
    /// scrollKey 予告 + render を評価する。recordRendered は render スクリプトを実際に
    /// evaluateJavaScript した後にのみ呼ぶ(呼び出し側で先行確定しないこと。直接 HTML
    /// モード離脱時のように呼び出しが pendingUpdate 経由で遅延・破棄されうる場合、
    /// 先行確定するとミラーが「描画済み」と偽り、以後の再描画が需要判定で握り潰される)。
    /// 画像埋め込み(embeddedContent)は MainActor 外で行うため、完了後に
    /// contentUpdateGeneration が呼び出し時から変わっていないか確認してから
    /// evaluateJavaScript/recordRendered を行う(後続の updateContent に追い越された場合は破棄)。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    func applyRender(
        webView: WKWebView, request: RenderRequest,
        restoreFromPersistedPosition: Bool
    ) async {
        let (content, contentRevision, fileType, filePath, isSourceMode, showLineNumbers, truncation, generation) = (
            request.content, request.contentRevision, request.fileType, request.filePath,
            request.isSourceMode, request.showLineNumbers, request.truncation, request.generation
        )
        if showLineNumbers != rendered.showLineNumbers {
            webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers), completionHandler: nil)
            rendered.showLineNumbers = showLineNumbers
        }
        if isSourceMode != rendered.isSourceMode {
            webView.evaluateJavaScript(
                ViewerBridge.viewModeScript(.init(isSourceMode: isSourceMode)), completionHandler: nil
            )
            rendered.isSourceMode = isSourceMode
        }
        if truncation != rendered.truncation {
            webView.evaluateJavaScript(
                truncation.script,
                completionHandler: nil
            )
            rendered.truncation = truncation
        }

        let renderable = await embeddedContent(
            content, fileType: fileType, filePath: filePath, isSourceMode: isSourceMode
        )
        guard generation == contentUpdateGeneration else { return }

        guard let script = ViewerBridge.renderScript(content: renderable, fileType: fileType) else { return }
        if restoreFromPersistedPosition {
            webView.evaluateJavaScript(
                ViewerBridge.restoreScrollPositionScript(scrollPositionToRestore), completionHandler: nil
            )
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
        recordRendered(contentRevision: contentRevision, fileType: fileType, filePath: filePath)
    }

    /// 描画済みキャッシュを更新する。content 全文は保持せず contentRevision だけを
    /// 比較用に保存する。
    func recordRendered(
        contentRevision: Int, fileType: FileType, filePath: URL?
    ) {
        rendered.contentRevision = contentRevision
        rendered.fileType = fileType
        rendered.filePath = filePath
    }

    /// pendingAppend の消費可否判定に必要な、更新後の描画条件をまとめた入力
    /// (function_parameter_count 対策)。
    struct PendingAppendCheck {
        let contentRevision: Int
        let showLineNumbers: Bool
        let filePath: URL?
        let isSourceMode: Bool
    }

    /// pendingAppend(段階読み込みでステージされた次チャンク)を全文 render せず増分描画して
    /// よいかどうかを判定する。revision 不一致・ファイル/モード切替に加え、直近描画時から
    /// showLineNumbers が変化している場合も全文 render 側へ倒す。同一 revision で pending
    /// append と行番号トグルが1つの @Observable サイクルに合体すると、増分追記だけを行い
    /// setLineNumbers() の注入が起きない applyAppend 経路へ吸収されてしまい、トグルが
    /// 1周期失われるため。
    nonisolated static func canConsumePendingAppend(
        _ pending: PendingAppend, _ current: PendingAppendCheck, rendered: RenderedStateMirror
    ) -> Bool {
        pending.revision == current.contentRevision
            && current.showLineNumbers == rendered.showLineNumbers
            && !isFileOrModeSwitch(
                filePath: current.filePath, isSourceMode: current.isSourceMode,
                lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
            )
    }

    /// 呼び出し前に `exitDirectHTMLMode` が `rendered.reset()` でミラーを一括破棄済みである
    /// 前提。再ロードで viewer.html の JS 状態(_mmdViewOptions: 行番号 false, モード rendered)が
    /// 初期化されるのに合わせ、次回更新時に setLineNumbers / setViewMode を再注入させる。
    func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
        isReady = false
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
