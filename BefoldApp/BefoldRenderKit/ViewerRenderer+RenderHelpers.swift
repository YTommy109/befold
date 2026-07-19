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
            guard let result = await onLoadMoreLines?() else { return }
            // updateContent が消費する前に次の続き読み込みが完了した場合(SwiftUI 更新の
            // 合体)に備え、未消費チャンクへ連結する。上書きすると先行チャンクが DOM へ
            // 追記されないまま失われるため、必ず累積する。revision は最新値を採る。
            let combinedChunk = (pendingAppend?.chunk ?? "") + result.chunk
            pendingAppend = PendingAppend(chunk: combinedChunk, revision: result.contentRevision)
        }
    }

    /// pendingAppend を消費して次チャンクを増分追記する(全文 render しない)。
    /// truncation は updateContent が受け取った現在値をそのまま使う。
    /// chunk が空(チャンク読込エラーのセンチネル)の場合は追記せず、切り詰めバナーだけ更新する。
    func applyAppend(
        webView: WKWebView, chunk: String, contentRevision: Int,
        fileType: FileType, filePath: URL?, truncation: TruncationState
    ) {
        rendered.truncation = truncation
        if !chunk.isEmpty, let script = ViewerBridge.appendChunkScript(chunk: chunk, fileType: fileType) {
            webView.evaluateJavaScript(script)
        }
        webView.evaluateJavaScript(
            ViewerBridge.truncatedScript(
                truncation.isTruncated, lineCount: truncation.lineCount, failed: truncation.failed
            )
        )
        recordRendered(contentRevision: contentRevision, fileType: fileType, filePath: filePath)
    }

    /// last* キャッシュとの差分を見て lineNumbers / viewMode を同期し、
    /// scrollKey 予告 + render を評価する。recordRendered は render スクリプトを実際に
    /// evaluateJavaScript した後にのみ呼ぶ(呼び出し側で先行確定しないこと。直接 HTML
    /// モード離脱時のように呼び出しが pendingUpdate 経由で遅延・破棄されうる場合、
    /// 先行確定するとミラーが「描画済み」と偽り、以後の再描画が需要判定で握り潰される)。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    func applyRender(
        webView: WKWebView, request: RenderRequest,
        restoreFromPersistedPosition: Bool
    ) {
        let (content, contentRevision, fileType, filePath, isSourceMode, showLineNumbers, truncation) = (
            request.content, request.contentRevision, request.fileType, request.filePath,
            request.isSourceMode, request.showLineNumbers, request.truncation
        )
        if showLineNumbers != rendered.showLineNumbers {
            webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers))
            rendered.showLineNumbers = showLineNumbers
        }
        if isSourceMode != rendered.isSourceMode {
            webView.evaluateJavaScript(
                ViewerBridge.viewModeScript(isSourceMode ? .source : .rendered)
            )
            rendered.isSourceMode = isSourceMode
        }
        if truncation != rendered.truncation {
            webView.evaluateJavaScript(
                ViewerBridge.truncatedScript(
                    truncation.isTruncated, lineCount: truncation.lineCount, failed: truncation.failed
                )
            )
            rendered.truncation = truncation
        }
        guard let script = ViewerBridge.renderScript(
            content: Self.renderableContent(
                content, fileType: fileType,
                filePath: filePath, isSourceMode: isSourceMode,
                embedImages: rendererFeatures.embedImages
            ),
            fileType: fileType
        ) else { return }
        if restoreFromPersistedPosition {
            webView.evaluateJavaScript(ViewerBridge.restoreScrollPositionScript(scrollPositionToRestore))
        }
        webView.evaluateJavaScript(script)
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

    /// 呼び出し前に `exitDirectHTMLMode` が `rendered.reset()` でミラーを一括破棄済みである
    /// 前提。再ロードで viewer.html の JS 状態(_showLineNumbers=false, _viewMode='rendered')が
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
        embedImages: Bool = true
    ) -> String {
        guard !isSourceMode, fileType == .markdown, let filePath, embedImages else { return content }
        return MarkdownImageEmbedder.embedLocalImages(in: content, baseURL: filePath)
    }
}
