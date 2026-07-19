import BefoldKit
import WebKit

// MARK: - One-shot rendering

public extension ViewerRenderer {
    /// ViewerLoadPipeline.Outcome を初回描画に必要な値へ写した静的スナップショット。
    /// 段階読み込みの継続やライブリロードを持たない1回描画ホスト(QuickLook 拡張等)向けに、
    /// ViewerStore.apply が持つ dataHash キャッシュ・世代管理・chunkSession 保持を省いた
    /// 最小構成。rejectReason が非 nil の場合、ホストはコンテンツ描画の代わりに
    /// 非対応表示(RejectReason.localizedMessage)を出すために使う。
    struct OneShotRender: Equatable, Sendable {
        public let content: String
        public let fileType: FileType
        public let filePath: URL?
        public let rejectReason: RejectReason?
        public let truncation: TruncationState

        public init(
            content: String, fileType: FileType, filePath: URL?,
            rejectReason: RejectReason?, truncation: TruncationState
        ) {
            self.content = content
            self.fileType = fileType
            self.filePath = filePath
            self.rejectReason = rejectReason
            self.truncation = truncation
        }
    }

    /// loadOneShot の結果。構成済みの WKWebView と、非対応判定の理由を返す。
    /// rejectReason が非 nil のとき、WebView は空の viewer.html を表示したままになるため、
    /// ホストは非対応メッセージを重ねて表示する。
    struct OneShotResult {
        public let webView: WKWebView
        public let rejectReason: RejectReason?
    }

    /// ViewerLoadPipeline.Outcome を OneShotRender へ変換する純粋ロジック。
    /// ViewerStore.apply の Outcome 分岐(chunked=先頭チャンク+切り詰め、full=全量+rejectReason)を、
    /// 状態遷移を伴わない値変換だけに落とし込んだもの。missing は QuickLook では対象ファイルが
    /// 常に存在するため通常発生しないが、安全側に unsupportedFormat として非対応表示へ倒す。
    nonisolated static func oneShotRender(
        from outcome: ViewerLoadPipeline.Outcome, url: URL, fileType: FileType
    ) -> OneShotRender {
        switch outcome {
        case .missing:
            OneShotRender(
                content: "", fileType: fileType, filePath: url,
                rejectReason: .unsupportedFormat,
                truncation: TruncationState(isTruncated: false, lineCount: 0, failed: false)
            )
        case let .chunked(_, _, firstChunk, isAtEnd):
            OneShotRender(
                content: firstChunk, fileType: fileType, filePath: url,
                rejectReason: nil,
                truncation: TruncationState(
                    isTruncated: !isAtEnd,
                    lineCount: displayedLineCount(of: firstChunk),
                    failed: false
                )
            )
        case let .full(loaded, _):
            OneShotRender(
                content: loaded.content, fileType: fileType, filePath: url,
                rejectReason: loaded.rejectReason,
                truncation: TruncationState(isTruncated: false, lineCount: 0, failed: false)
            )
        }
    }

    /// 蓄積済み content の改行数から表示行数を求める(ViewerStore.updateDisplayedLineCount と同じ規則)。
    /// 末尾が改行で終わらない場合、その途中の行も表示中の1行として数える。
    nonisolated static func displayedLineCount(of content: String) -> Int {
        let newlines = content.utf8.count(where: { $0 == 0x0A })
        let hasTrailingPartialLine = !content.isEmpty && content.utf8.last != 0x0A
        return newlines + (hasTrailingPartialLine ? 1 : 0)
    }

    /// ファイル URL から WebView 構成と初回描画までを1呼び出しで行う one-shot 合成 API。
    /// ViewerLoadPipeline.load(oneShotLoad: true) で静的に読み込み、makeWebView で viewer.html を
    /// 構成し、updateContent で初回描画を予約する(ロード完了まで pendingUpdate で保留される)。
    /// QuickLook 拡張のように親ディレクトリ・兄弟ファイルへの read 権限がないホストでは、
    /// rendererFeatures にブリッジ・直接 HTML・画像埋め込みを無効化した構成を事前にセットしておく。
    /// - Parameters:
    ///   - url: 表示するファイルの URL。
    ///   - fileType: 明示する場合の種別。nil の場合は拡張子から判定する。
    ///   - fileReader: I/O 抽象。テストでは InMemoryFileReader を注入する。
    ///   - chunkedReaderFactory: 行指向ファイルのチャンクリーダー生成。
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    @discardableResult
    func loadOneShot(
        url: URL,
        fileType: FileType? = nil,
        fileReader: any FileReading = DefaultFileReader(),
        chunkedReaderFactory: @escaping ViewerLoadPipeline.ChunkedReaderFactory = { cache, fileType in
            StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
        },
        initialZoom: Double = 1.0
    ) async -> OneShotResult {
        let resolvedFileType = fileType ?? FileType(url: url)
        let outcome = await ViewerLoadPipeline.load(
            resolved: url.resolvingSymlinksInPath(),
            fileType: resolvedFileType,
            fileReader: fileReader,
            contentLoader: ContentLoader(fileReader: fileReader),
            chunkedReaderFactory: chunkedReaderFactory,
            oneShotLoad: true
        )
        let render = Self.oneShotRender(from: outcome, url: url, fileType: resolvedFileType)

        let webView = makeWebView(initialZoom: initialZoom, findOptionsPreference: nil)
        updateContent(
            render.content,
            contentRevision: 1,
            fileType: render.fileType,
            filePath: render.filePath,
            isSourceMode: false,
            showLineNumbers: false,
            truncation: render.truncation
        )
        return OneShotResult(webView: webView, rejectReason: render.rejectReason)
    }
}
