import BefoldKit
import Foundation

/// 読み込み経路。pendingURL の内容をバックグラウンドで取得し、着地した結果を
/// 表示状態へ渡す（書き換え自体は `ViewerContentState` の internal な入口が行う）。
/// 段階読み込み（チャンク）の続き取得もここが担う。
@MainActor
extension ViewerStore {
    /// 次のチャンクを読み込んで content に追記し、表示状態を返す。
    /// 末尾に達している・セッションがない場合は nil を返す。
    /// 戻り値の contentRevision は追記後の世代番号(呼び出し側が描画済みキャッシュを
    /// 同期し、直後の全文 render 誤爆を防ぐために使う)。
    func loadMoreLines() async -> LoadMoreLinesResult? {
        guard contentState.isTruncated, let session = contentState.chunkSession else { return nil }
        do {
            let result = try await session.readNextChunk()
            // 読み込み待機中の再読込(セッション交代)と競合した場合は、
            // 古いセッションの結果を捨てて新しい表示を壊さない。
            guard contentState.chunkSession === session else { return nil }
            contentState.appendChunk(result.text, isAtEnd: result.isAtEnd)
            return LoadMoreLinesResult(
                chunk: result.text, isTruncated: contentState.isTruncated,
                lineCount: contentState.displayedLineCount,
                contentRevision: contentState.contentRevision,
                loadFailed: false
            )
        } catch {
            guard contentState.chunkSession === session else { return nil }
            // セッション途中のエラーではチャンクセッションを終了し、
            // 表示済みの内容を保持する。loadContent で全体を再読込すると、
            // 10MB 超のファイルで表示済みコンテンツが fileTooLarge に置き換わるため。
            contentState.markChunkLoadFailed()
            return LoadMoreLinesResult(
                chunk: "", isTruncated: contentState.isTruncated,
                lineCount: contentState.displayedLineCount,
                contentRevision: contentState.contentRevision,
                loadFailed: true
            )
        }
    }

    /// pendingURL の読み込みを予約する。I/O・デコードはバックグラウンドで行い、
    /// 完了後にメインアクターで表示状態へ一括適用する。呼び出しごとに世代番号を進め、
    /// 追い越された古い読み込みの結果は破棄する。
    func loadContent() {
        guard let target = pendingURL else { return }
        loadGeneration += 1
        let generation = loadGeneration
        contentState.beginLoading()
        let resolved = target.resolvingSymlinksInPath()
        let fileType = pendingFileType
        loadTask = Task {
            await self.performLoad(
                resolved: resolved, url: target, fileType: fileType,
                generation: generation
            )
        }
    }

    /// バックグラウンドで読み込み結果を計算し、世代が最新のままなら表示状態へ適用する。
    private func performLoad(
        resolved: URL, url: URL, fileType: FileType, generation: Int
    ) async {
        let outcome = await ViewerLoadPipeline.load(
            resolved: resolved,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: makeChunkedReader
        )
        // close() でキャンセルされた、または新しい読み込みに追い越された結果は捨てる。
        guard !Task.isCancelled, generation == loadGeneration else { return }
        apply(outcome, url: url, fileType: fileType)
    }

    /// 読み込み結果を表示状態(filePath / fileType / content / rejectReason / isTruncated /
    /// 行数カウンタ / chunkSession)へ一括適用する。読み込み結果の種別ごとの差分は
    /// DisplayState の組み立てだけに閉じ込め、実際の書き換えは applyDisplayState に一本化する。
    /// filePath / fileType を content と同時にここで確定させることで、旧ファイルの content に
    /// 新ファイルの filePath や fileType が組み合わさった中間状態が描画されないようにする
    /// (task: HTML 表示直後の切替で空白表示になる不具合の再発防止)。
    private func apply(_ outcome: ViewerLoadPipeline.Outcome, url: URL, fileType: FileType) {
        contentState.finishLoading(url: url)
        let state: ViewerContentState.DisplayState
        switch outcome {
        case .missing:
            scheduleFileGone()
            return
        case let .chunked(session, cache, firstChunk, isAtEnd):
            state = ViewerContentState.DisplayState(
                fileType: fileType,
                contentHash: cache.dataHash,
                chunkSession: session,
                rejectReason: nil,
                isTruncated: !isAtEnd,
                content: firstChunk,
                tracksLineCount: true,
                hasDeclaredHTMLCharset: nil
            )
        case let .full(loaded, cache):
            state = ViewerContentState.DisplayState(
                fileType: fileType,
                contentHash: cache?.dataHash,
                chunkSession: nil,
                rejectReason: loaded.rejectReason,
                isTruncated: false,
                content: loaded.content,
                tracksLineCount: false,
                hasDeclaredHTMLCharset: loaded.hasDeclaredHTMLCharset
            )
        }
        guard contentState.applyDisplayState(state) else { return }
        fileGoneWatchdog.cancel()
        // rejectReason / content(表示状態)が確定した後に通知する。
        onContentReloaded?()
    }
}
