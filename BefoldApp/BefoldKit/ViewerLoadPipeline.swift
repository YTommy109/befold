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
    public static func load(
        resolved: URL,
        fileType: FileType,
        fileReader: any FileReading,
        contentLoader: ContentLoader,
        chunkedReaderFactory: ChunkedReaderFactory
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
                let cache = try NormalizedTextCache(data: data, normalizeFully: false)
                let reader = try chunkedReaderFactory(cache, fileType)
                let firstChunk = try await reader.readNextChunk()
                return .chunked(
                    session: reader, cache: cache,
                    firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
                )
            } else {
                let cache = try NormalizedTextCache(data: data)
                if cache.text.utf8.count > ContentLoader.maxTextFileSizeBytes {
                    return .full(
                        ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                        cache: nil
                    )
                }
                return .full(
                    ContentLoader.LoadedContent(rejectReason: nil, content: cache.text),
                    cache: cache
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
}
