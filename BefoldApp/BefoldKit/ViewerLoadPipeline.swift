import Foundation

/// ファイルの静的な読み込み(存在確認・NormalizedTextCache 生成・チャンクセッション生成・全量読み込み)を
/// 行う純粋なロジック。ViewerStore の watcher・UserDefaults・onFileGone 等のオーケストレーションから
/// 独立しているため、QuickLook 拡張のような1回描画のみを必要とするホストからも再利用できる。
public enum ViewerLoadPipeline {
    /// チャンクリーダーの生成(ファイルを開いて先頭をプローブする)を行うファクトリ。
    /// バックグラウンドの読み込みタスクから呼ばれるため、アクター隔離しない。
    public typealias ChunkedReaderFactory = @Sendable (NormalizedTextCache, FileType) throws -> any ChunkedTextReading

    /// 読み込みの結果。呼び出し側(ViewerStore)がメインアクターへ持ち帰って一括適用する。
    public enum Outcome: Sendable {
        /// ファイルが存在しない(削除グレース期間を開始する)。
        case missing
        /// 行指向ファイルのチャンクセッションを開始し、先頭チャンクを読み込んだ。
        case chunked(session: any ChunkedTextReading, cache: NormalizedTextCache, firstChunk: String, isAtEnd: Bool)
        /// 全量読み込みの結果(rejectReason を含みうる)。
        case full(ContentLoader.LoadedContent, cache: NormalizedTextCache?)
    }

    /// ファイルの存在確認・NormalizedTextCache 生成・チャンクセッション生成・全量読み込みを行う。
    /// nonisolated async のため呼び出し元のアクターを離れて実行され、
    /// I/O・デコードがメインスレッドを塞がない。
    /// oneShotLoad: true の場合、ライブリロードの同一内容スキップにしか使わない dataHash の
    /// 計算とエンコーディング判定の全量フォールバックスキャンを省略する(QuickLook 拡張のような
    /// 1回描画のみのホスト向け。詳細は NormalizedTextCache.init 参照)。ViewerStore は
    /// 同一内容スキップに dataHash を必要とするため既定の false のまま呼び出す。
    /// embedLocalImages: markdown 内のローカル画像を MarkdownImageEmbedder のキャッシュへ
    /// ウォームアップするかどうか。render 経路(ViewerRenderer+RenderHelpers.swift)は
    /// 従来どおり render 直前に embedLocalImages を呼ぶが、ここで先に同じ (mtime, size) キーの
    /// キャッシュを温めておくことで、render 側の呼び出しをメインスレッド上のディスク読込・
    /// base64 エンコード無しのキャッシュヒットにする。ホストが画像埋め込みを無効化する場合
    /// (QuickLook 等、rendererFeatures.embedImages == false)は false を渡し、
    /// 読込権限のないファイルへ触れないようにする。
    public static func load(
        resolved: URL,
        fileType: FileType,
        fileReader: any FileReading,
        contentLoader: ContentLoader,
        chunkedReaderFactory: ChunkedReaderFactory,
        oneShotLoad: Bool = false,
        embedLocalImages: Bool = true
    ) async -> Outcome {
        guard fileReader.fileExists(at: resolved) else { return .missing }

        if fileType.isBinaryContent {
            return .full(contentLoader.load(from: resolved, fileType: fileType), cache: nil)
        }

        if fileReader.isBinary(at: resolved) {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .unsupportedFormat, content: ""),
                cache: nil
            )
        }

        let sizeLimit = fileType.isLineOriented
            ? NormalizedTextCache.maxFileSizeBytes
            : ContentLoader.maxTextFileSizeBytes
        if let size = fileReader.fileSize(at: resolved), size > sizeLimit {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                cache: nil
            )
        }

        do {
            let data = try fileReader.readData(from: resolved)

            if fileType.isLineOriented {
                // 先頭チャンク描画に必要な範囲だけを正規化・行分割する
                // (ファイル全体を materialize しない。100MB 級ファイルでの
                // ピークメモリ・CPU 削減のため。詳細は NormalizedTextCache 参照)。
                let cache = try NormalizedTextCache(data: data, normalizeFully: false, oneShotLoad: oneShotLoad)
                let reader = try chunkedReaderFactory(cache, fileType)
                let firstChunk = try await reader.readNextChunk()
                return .chunked(
                    session: reader, cache: cache,
                    firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
                )
            } else {
                return try loadFull(
                    data: data, resolved: resolved, fileType: fileType,
                    oneShotLoad: oneShotLoad, embedLocalImages: embedLocalImages
                )
            }
        } catch {
            if !fileReader.fileExists(at: resolved) { return .missing }
            // 事前サイズチェックをすり抜けた場合(fileSize が nil を返した、または
            // チェック後にファイルが肥大化した TOCTOU)、NormalizedTextCache.init が
            // fileTooLarge を投げる。これを unsupportedFormat に丸めず理由を保持する。
            let reason: RejectReason = error is NormalizedTextCacheError ? .fileTooLarge : .unsupportedFormat
            return .full(
                ContentLoader.LoadedContent(rejectReason: reason, content: ""),
                cache: nil
            )
        }
    }

    /// 非行指向(markdown/mmd/svg/html)の全量読み込み。markdown の場合、embedLocalImages が
    /// true なら render 直前の MarkdownImageEmbedder 呼び出しに先立ちキャッシュをウォームアップする
    /// (詳細は load のドキュメントコメント参照)。
    private static func loadFull(
        data: Data, resolved: URL, fileType: FileType,
        oneShotLoad: Bool, embedLocalImages: Bool
    ) throws -> Outcome {
        let cache = try NormalizedTextCache(data: data, oneShotLoad: oneShotLoad)
        if cache.text.utf8.count > ContentLoader.maxTextFileSizeBytes {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                cache: nil
            )
        }
        if embedLocalImages, fileType == .markdown {
            // render 経路と同じキャッシュを温めるため、共有インスタンスを経由すること。
            _ = MarkdownImageEmbedder.shared.embedLocalImages(in: cache.text, baseURL: resolved)
        }
        return .full(
            ContentLoader.LoadedContent(rejectReason: nil, content: cache.text),
            cache: cache
        )
    }
}
