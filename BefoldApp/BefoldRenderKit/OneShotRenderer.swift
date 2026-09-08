import BefoldKit
import BefoldPDFProbe
import WebKit

/// ViewerLoadPipeline.Outcome を初回描画に必要な値へ写した静的スナップショット。
/// 段階読み込みの継続やライブリロードを持たない1回描画ホスト(QuickLook 拡張等)向けに、
/// ViewerStore.apply が持つ dataHash キャッシュ・世代管理・chunkSession 保持を省いた
/// 最小構成。rejectReason が非 nil の場合、ホストはコンテンツ描画の代わりに
/// 非対応表示(RejectReason.localizedMessage)を出すために使う。
public struct OneShotRender: Equatable, Sendable {
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

/// `OneShotRenderer.load` の結果。構成済みの WKWebView と、非対応判定の理由を返す。
/// rejectReason が非 nil のとき、WebView は空の viewer.html を表示したままになるため、
/// ホストは非対応メッセージを重ねて表示する。
public struct OneShotResult {
    public let webView: WKWebView
    public let rejectReason: RejectReason?
}

/// ファイル URL から WebView 構成と初回描画までを 1 呼び出しで行う合成 API。
///
/// ライブリロード用のレンダラ(ViewerRenderer)を**内包**する。継承や extension に
/// しないのは、1 回描画ホストに再描画・段階読み込み・差分表示のための状態を
/// 一切見せないため。QuickLook 拡張のように親ディレクトリ・兄弟ファイルへの
/// read 権限がないホストは、features に `.quickLookRestricted` を渡す。
@MainActor
public final class OneShotRenderer {
    private let renderer = ViewerRenderer()

    /// 描画完了(mermaid 等の非同期描画を含む)を待つ上限。QuickLook のプレビュー生成を
    /// ハングさせないための保険で、超過した場合はその時点の DOM のまま完了として返す。
    /// 負荷の高いテスト環境など、ホスト側の事情で待ち時間を伸ばしたい場合に差し替える。
    public var renderTimeout: Duration = .seconds(3)

    /// 直近に構成した WebView。内包するレンダラが保持し続けていること
    /// (描画完了前に解放されないこと)をテストから確認するためのもの。
    /// **残している downcast（TASK-599）。** テストが「内包するレンダラが描画完了まで
    /// 面を保持し続けている」ことを確かめるためだけの窓で、本番の描画経路は通らない。
    /// 境界へ出すと「実体の NSView を寄越せ」という WebKit 固有の要求が
    /// `RenderSurface` の語彙に混ざるため、ここに閉じてある。
    var webView: WKWebView? {
        (renderer.surface as? WebKitRenderSurface)?.webView
    }

    /// 直近に構成した描画面。内部の描画はこちらを通す。
    private var surface: (any RenderSurface)? {
        renderer.surface
    }

    public init(features: RendererFeatures = .allEnabled) {
        renderer.rendererFeatures = features
    }

    /// ViewerLoadPipeline.Outcome を OneShotRender へ変換する純粋ロジック。
    /// ViewerStore.apply の Outcome 分岐(chunked=先頭チャンク+切り詰め、full=全量+rejectReason)を、
    /// 状態遷移を伴わない値変換だけに落とし込んだもの。missing は QuickLook では対象ファイルが
    /// 常に存在するため通常発生しないが、安全側に unsupportedFormat として非対応表示へ倒す。
    public nonisolated static func render(
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
                    lineCount: DisplayedLineCount.count(of: firstChunk),
                    failed: false
                )
            )
        case let .binary(loaded):
            // PDF の生データ経路。1 回描画ホスト(QuickLook)は PDF を扱わない
            // (`FileType.quickLookSupportedExtensions` が `isBinaryContent` を除く)ため
            // ここへは来ないが、拒否理由だけは落とさずに運ぶ。
            OneShotRender(
                content: "", fileType: fileType, filePath: url,
                rejectReason: loaded.rejectReason ?? .unsupportedFormat,
                truncation: TruncationState(isTruncated: false, lineCount: 0, failed: false)
            )
        case let .full(loaded, _):
            OneShotRender(
                content: loaded.content, fileType: fileType, filePath: url,
                rejectReason: loaded.rejectReason,
                truncation: TruncationState(isTruncated: false, lineCount: 0, failed: false)
            )
        }
    }

    /// ViewerLoadPipeline.load(oneShotLoad: true) で静的に読み込み、viewer.html を構成し、
    /// 初回描画の完了まで待つ。
    /// - Parameters:
    ///   - url: 表示するファイルの URL。
    ///   - fileType: 明示する場合の種別。nil の場合は拡張子から判定する。
    ///   - fileReader: I/O 抽象。テストでは InMemoryFileReader を注入する。
    ///   - chunkedReaderFactory: 行指向ファイルのチャンクリーダー生成。
    ///   - initialZoom: ロード前に JS へ注入する初期倍率。
    @discardableResult
    public func load(
        url: URL,
        fileType: FileType? = nil,
        fileReader: any FileReading = DefaultFileReader(),
        chunkedReaderFactory: @escaping ViewerLoadPipeline.ChunkedReaderFactory =
            ViewerLoadPipeline.defaultChunkedReaderFactory,
        initialZoom: Double = 1.0
    ) async -> OneShotResult {
        let resolvedFileType = fileType ?? FileType(url: url)
        let outcome = await ViewerLoadPipeline.load(
            ViewerLoadPipeline.Inputs(
                resolved: url.resolvingSymlinksInPath(),
                fileType: resolvedFileType,
                fileReader: fileReader,
                chunkedReaderFactory: chunkedReaderFactory,
                isPDFReadable: PDFDataProbe.isReadable
            ),
            oneShotLoad: true,
            embedLocalImages: renderer.rendererFeatures.embedImages
        )
        let render = Self.render(from: outcome, url: url, fileType: resolvedFileType)

        // ホスト（QuickLook 拡張）がプレビューへ埋め込む NSView を返す必要があるため、
        // ここは実装型を保ったまま構成する。構成経路はアプリ側と同じ 1 本。
        let surface = WebKitRenderSurface.make(
            for: renderer, initialZoom: initialZoom, findOptionsPreference: nil
        )
        // QuickLook では allowDirectHTML=false のため HTML も viewer.html 内の iframe で
        // 描くが、外部の HTML 文書であることは変わらないので canvas は文書に所有させる
        // (透過のままだと子文書の color-scheme 宣言が届かない。setDocumentOwnsCanvas 参照)。
        // renderOnce は常に isSourceMode: false で描画する。
        surface.setDocumentOwnsCanvas(
            ViewerWebViewFactory.documentOwnsCanvas(
                fileType: resolvedFileType, isSourceMode: false
            )
        )
        if render.rejectReason == nil {
            await renderOnce(surface: surface, render: render)
        }
        return OneShotResult(webView: surface.webView, rejectReason: render.rejectReason)
    }

    /// viewer.html のロード完了を待ってから 1 回だけ描画し、その完了までを await する。
    /// 通常ホストの updateContent 経路(fire-and-forget な evaluateJavaScript と
    /// 差分判定用の rendered ミラー)は使わない。1 回しか描画しないため差分判定が不要で、
    /// かつ描画完了を待つには render() の返す Promise を callAsyncJavaScript で
    /// 受け取る必要があるため、専用の一本道にしている。
    private func renderOnce(surface: any RenderSurface, render: OneShotRender) async {
        guard let script = ViewerBridge.awaitRenderScript(
            content: RenderableContent.make(
                render.content, fileType: render.fileType,
                filePath: render.filePath, isSourceMode: false,
                embedImages: renderer.rendererFeatures.embedImages
            ),
            fileType: render.fileType
        ) else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let completion = OneShotCompletion(continuation: continuation)
            Task { @MainActor in
                try? await Task.sleep(for: renderTimeout)
                completion.finish()
            }

            // viewer.html のロード完了を待つゲートは既存の pendingUpdate をそのまま使う
            // (didFinish / ナビゲーション失敗のどちらでも必ず呼ばれる)。
            let evaluate: @MainActor () -> Void = { [weak self] in
                _ = Task { @MainActor in
                    guard let surface = self?.surface else {
                        completion.finish()
                        return
                    }
                    if render.truncation.isTruncated {
                        surface.evaluateScript(render.truncation.script, completion: nil)
                    }
                    _ = try? await surface.callScript(script)
                    completion.finish()
                }
            }
            renderer.runWhenReady(evaluate)
        }
    }
}

/// one-shot 描画の待ち合わせを 1 回だけ再開するための箱。
/// 描画完了とタイムアウトのどちらが先に来ても安全に解決できるようにする
/// (CheckedContinuation の二重再開はクラッシュするため)。
@MainActor
private final class OneShotCompletion {
    private var continuation: CheckedContinuation<Void, Never>?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
