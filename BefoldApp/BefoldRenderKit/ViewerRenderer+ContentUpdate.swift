import BefoldKit
import WebKit

// MARK: - Content update

public extension ViewerRenderer {
    /// 表示内容の更新要求を受ける唯一の sink。
    /// 何をするかの判断は ContentUpdatePlanner(純関数)に任せ、ここは実行だけを行う。
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
        let input = ContentUpdateInput(
            content: content, contentRevision: contentRevision, fileType: fileType,
            filePath: filePath, hasDeclaredHTMLCharset: hasDeclaredHTMLCharset,
            isSourceMode: isSourceMode, showLineNumbers: showLineNumbers,
            truncation: truncation, generation: contentUpdateGeneration, diffState: diffState
        )

        runWhenReady { [weak self] in
            guard let self, let webView else { return }
            let plan = plan(for: input)
            execute(plan, input: input, webView: webView)
            // 倍率は**描き直すときだけ**、内容と同じ同期区間で当てる。
            //
            // `updateContent` はホストの状態が変わるたびに呼ばれ、内容に差が無ければ
            // `.skip` になる。ファイルを切り替えた直後はまさにこれで、画面には前の
            // ファイルが出たまま「新しいファイルの倍率」だけが流し込まれている。
            // ここで当てると、切り替わる前のファイルの倍率が変わる
            // (TASK-567 の実測。`PageZoomProjector.desired` の doc も参照)。
            guard plan != .skip else { return }
            pageZoom.applyIfReady()
        }
    }
}

extension ViewerRenderer {
    /// 実行時点(保留から解けた時点)の状態で計画を立てる。
    /// pendingAppend は消費可否にかかわらずここで捨てる。持ち越すと、追記に倒せなかった
    /// 入力の後で古いチャンクが別の内容へ適用されうる。
    private func plan(for input: ContentUpdateInput) -> UpdatePlan {
        let pending = pendingAppend
        pendingAppend = nil
        return ContentUpdatePlanner.plan(
            input: input, rendered: rendered, pendingAppend: pending,
            isDirectHTMLActive: directHTML.isActive, features: rendererFeatures
        )
    }

    private func execute(_ plan: UpdatePlan, input: ContentUpdateInput, webView: WKWebView) {
        switch plan {
        case let .directHTMLLoad(filePath):
            _ = directHTML.enter(
                webView: webView, filePath: filePath,
                request: DirectHTMLLoadRequest(
                    content: input.content, contentRevision: input.contentRevision,
                    fileType: input.fileType, isSourceMode: input.isSourceMode,
                    hasDeclaredHTMLCharset: input.hasDeclaredHTMLCharset
                )
            )
        case let .exitDirectThenRender(request, restore):
            directHTML.exit(webView: webView) { [weak self] in
                self?.scheduleRender(webView: webView, request: request, restoreFromPersistedPosition: restore)
            }
        case let .append(request):
            Task { @MainActor in
                await self.scriptDispatcher.applyAppend(webView: webView, request: request)
            }
        case let .render(request, restore):
            scheduleRender(webView: webView, request: request, restoreFromPersistedPosition: restore)
        case .skip:
            break
        }
    }

    private func scheduleRender(
        webView: WKWebView, request: RenderRequest, restoreFromPersistedPosition: Bool
    ) {
        Task { @MainActor in
            await self.scriptDispatcher.applyRender(
                webView: webView, request: request,
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }
    }
}
