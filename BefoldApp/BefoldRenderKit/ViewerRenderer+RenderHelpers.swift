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

    /// 呼び出し前に `DirectHTMLModeController.exit` が空のミラーを確定させて一括破棄済みで
    /// ある前提。再ロードで viewer.html の JS 状態(_mmdViewOptions: 行番号 false, モード rendered)が
    /// 初期化されるのに合わせ、次回更新時に setLineNumbers / setViewMode を再注入させる。
    func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
        readiness.markNotReady()
        // 読み直すと JS 側の状態(参照解決の FIFO キューを含む)が捨てられる。飛行中の
        // 応答を新しいページへ適用しないよう世代を進める(TASK-421)。
        referenceQueue.invalidate()
        // atDocumentStart の initialZoomScript はウィンドウ生成時の倍率で焼き付いているが、
        // 呼び出し元の exit が appliedPageZoom を捨てているため、ロード完了時の
        // applyInitialPageZoomIfReady が現在ファイルの保存倍率を当て直す。ここで重ねて
        // 当てない(同じ倍率を 2 度流すだけで、appliedPageZoom の記録も経由しない)。
        readiness.run(completion)
        // viewer.html（mermaid.js）は JS 必須のため、直接ロードで無効化した JS を再有効化する。
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // canvas の所有権も同時に戻す。viewer.html を描くのは befold なので透過が既定
        // （ここへ戻る経路に外部 HTML 文書はない。ソース表示の HTML は code として描く）。
        ViewerWebViewFactory.setDocumentOwnsCanvas(false, on: webView)
        // canvas の所有権も同時に戻す。viewer.html を描くのは befold なので透過が既定
        // （ここへ戻る経路に外部 HTML 文書はない。ソース表示の HTML は code として描く）。
        ViewerWebViewFactory.loadViewerHTML(into: webView)
    }
}
