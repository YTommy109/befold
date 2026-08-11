import BefoldKit
import WebKit

// MARK: - Content update

extension ViewerRenderer {
    /// applyRender を非同期 Task で起動する(doUpdate 内の重複削減)。
    private func scheduleRender(webView: WKWebView, request: RenderRequest, restoreFromPersistedPosition: Bool) {
        Task { @MainActor in
            await self.applyRender(
                webView: webView, request: request,
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }
    }

    /// applyAppend を非同期 Task で起動する(doUpdate 内の重複削減)。
    private func scheduleAppend(webView: WKWebView, request: AppendRequest) {
        Task { @MainActor in
            await self.applyAppend(webView: webView, request: request)
        }
    }
}

public extension ViewerRenderer {
    /// 表示内容の更新要求を受ける唯一の sink。
    func updateContent(
        _ content: String,
        contentRevision: Int,
        fileType: FileType,
        filePath: URL?,
        hasDeclaredHTMLCharset: Bool?,
        isSourceMode: Bool,
        showLineNumbers: Bool,
        truncation: TruncationState
    ) {
        // 見えていない間は描画しない。描画済みミラー(rendered)も更新しないので、
        // 見える状態へ戻ってホストが呼び直したときに、最新の内容で 1 度だけ描画される。
        guard isVisible else { return }

        // この呼び出し固有の世代番号。applyRender/applyAppend は画像埋め込み(MainActor 外)から
        // 戻った際にこの値を渡し、後続の updateContent 呼び出しに追い越されていないかを確認する。
        contentUpdateGeneration += 1
        let generation = contentUpdateGeneration

        let doUpdate = { [weak self] in
            guard let self, let webView else { return }

            // HTML レンダリング表示: loadFileURL で直接ロード
            if DirectHTMLModeController.shouldEnter(
                fileType: fileType, isSourceMode: isSourceMode,
                filePath: filePath, features: rendererFeatures
            ), let filePath {
                _ = directHTML.enter(
                    webView: webView, filePath: filePath,
                    request: DirectHTMLLoadRequest(
                        content: content, contentRevision: contentRevision, fileType: fileType,
                        isSourceMode: isSourceMode, hasDeclaredHTMLCharset: hasDeclaredHTMLCharset
                    )
                )
                return
            }

            // 直接 HTML モードから viewer.html モードへの復帰
            if directHTML.isActive {
                // この分岐に来る時点でファイルかモードが直接HTML状態と必ず異なるため
                // (同一なら上の直接HTMLロード分岐に吸収される)、常に切替として扱われる。
                let restoreFromPersistedPosition = RenderedStateMirror.isFileOrModeSwitch(
                    filePath: filePath, isSourceMode: isSourceMode,
                    lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
                )
                let request = RenderRequest(
                    content: content, contentRevision: contentRevision, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode, showLineNumbers: showLineNumbers,
                    truncation: truncation, generation: generation
                )
                directHTML.exit(webView: webView) {
                    self.scheduleRender(
                        webView: webView, request: request,
                        restoreFromPersistedPosition: restoreFromPersistedPosition
                    )
                }
                return
            }

            // content・fileType だけでなく isSourceMode の変化でも再描画する。
            // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
            // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある。
            // 差分の到着・レイアウト変更も同様に別の DOM を作り直す)
            //
            // 個々のフィールドを並べて比較せず、描画済みミラーと同じ形の値を組んで
            // 丸ごと比較する。列挙にすると、ミラーへフィールドを足したときに
            // ここへの追加だけ漏れて「状態は変わったのに再描画されない」形の穴が空く。
            // 下の pendingAppend 消費可否も同じ値を使って判定する(判定が 2 箇所あるので、
            // 片方だけ列挙式で残すと同じ穴がそちらに空く)。
            let incoming = RenderedStateMirror(
                contentRevision: contentRevision, fileType: fileType, filePath: filePath,
                showLineNumbers: showLineNumbers, isSourceMode: isSourceMode,
                truncation: truncation, diffState: diffState
            )

            // 段階読み込みの続き(loadMoreLines)は handleLoadMoreLines が pendingAppend として
            // ステージする。追記で正しく更新できる差(内容の世代と切り詰め状態)しか無ければ
            // 全文 render せず増分追記する。これで「追記の描画」経路が updateContent 1 本に集約される。
            // 条件不一致(別の読み込みに追い越された・同一サイクルで行番号や差分の切替も
            // 起きた等)の場合は破棄し、下の通常経路で全文 render に倒す。
            if let pending = pendingAppend {
                pendingAppend = nil
                if RenderedStateMirror.canConsume(pending, incoming: incoming, rendered: rendered) {
                    scheduleAppend(
                        webView: webView,
                        request: AppendRequest(
                            chunk: pending.chunk, contentRevision: contentRevision,
                            fileType: fileType, filePath: filePath, isSourceMode: isSourceMode,
                            truncation: truncation, generation: generation
                        )
                    )
                    return
                }
            }

            guard incoming != rendered else { return }

            let restoreFromPersistedPosition = RenderedStateMirror.isFileOrModeSwitch(
                filePath: filePath, isSourceMode: isSourceMode,
                lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
            )
            scheduleRender(
                webView: webView,
                request: RenderRequest(
                    content: content, contentRevision: contentRevision, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode, showLineNumbers: showLineNumbers,
                    truncation: truncation, generation: generation
                ),
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }

        runWhenReady(doUpdate)
    }
}
