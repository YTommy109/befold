import BefoldKit
import WebKit

// MARK: - Render helpers

extension ViewerRenderer {
    /// 次チャンクを非同期で取得し、キャッシュ更新と描画を行う。読み込み中の再入は
    /// isLoadingMoreLines で無視し、追記の交錯を防ぐ。
    @MainActor
    func handleLoadMoreLines() {
        guard !isLoadingMoreLines else { return }
        isLoadingMoreLines = true
        Task { @MainActor [self] in
            defer { isLoadingMoreLines = false }
            guard let webView, let result = await onLoadMoreLines?() else { return }
            let truncation = TruncationState(
                isTruncated: result.isTruncated, lineCount: result.lineCount, failed: result.loadFailed
            )
            lastTruncation = truncation

            // JS 呼び出し(await)より前に同期でキャッシュを更新することで、追記後の
            // 呼び出し側の再描画による全文 render の誤爆と、チャンク二重表示レースの
            // 窓を閉じる(recordRendered 呼び出し前に他の処理へ制御が渡らない)。
            let fileType = lastRenderedFileType ?? FileType.plaintextFallback
            recordRendered(
                contentRevision: result.contentRevision,
                fileType: fileType, filePath: lastRenderedFilePath
            )

            // result.chunk が空(チャンク読込エラーのセンチネル)の場合は追記する
            // 内容がないため appendChunk 自体を呼ばない(幻の空行を防ぐ)。
            if !result.chunk.isEmpty, let script = ViewerBridge.appendChunkScript(
                chunk: result.chunk,
                fileType: fileType
            ) {
                _ = try? await webView.evaluateJavaScript(script)
            }
            _ = try? await webView.evaluateJavaScript(
                ViewerBridge.truncatedScript(
                    truncation.isTruncated, lineCount: truncation.lineCount, failed: truncation.failed
                )
            )
        }
    }

    /// last* キャッシュとの差分を見て lineNumbers / viewMode を同期し、
    /// scrollKey 予告 + render を評価する。
    /// - Parameter restoreFromPersistedPosition: `isFileOrModeSwitch` 参照。
    func applyRender(
        webView: WKWebView, content: String, fileType: FileType,
        filePath: URL?, isSourceMode: Bool, showLineNumbers: Bool,
        truncation: TruncationState,
        restoreFromPersistedPosition: Bool
    ) {
        if showLineNumbers != lastShowLineNumbers {
            webView.evaluateJavaScript(ViewerBridge.lineNumbersScript(showLineNumbers))
            lastShowLineNumbers = showLineNumbers
        }
        if isSourceMode != lastIsSourceMode {
            webView.evaluateJavaScript(
                ViewerBridge.viewModeScript(isSourceMode ? .source : .rendered)
            )
            lastIsSourceMode = isSourceMode
        }
        if truncation != lastTruncation {
            webView.evaluateJavaScript(
                ViewerBridge.truncatedScript(
                    truncation.isTruncated, lineCount: truncation.lineCount, failed: truncation.failed
                )
            )
            lastTruncation = truncation
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
    }

    /// 描画済みキャッシュを更新する。content 全文は保持せず contentRevision だけを
    /// 比較用に保存する。
    func recordRendered(
        contentRevision: Int, fileType: FileType, filePath: URL?
    ) {
        lastRenderedContentRevision = contentRevision
        lastRenderedFileType = fileType
        lastRenderedFilePath = filePath
    }

    func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
        isReady = false
        // 再ロードで viewer.html の JS 状態(_showLineNumbers=false, _viewMode='rendered')が
        // 初期化されるため、Swift 側のキャッシュも破棄して次回更新時に
        // setLineNumbers / setViewMode を再注入させる。
        lastShowLineNumbers = nil
        lastIsSourceMode = nil
        lastTruncation = nil
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
