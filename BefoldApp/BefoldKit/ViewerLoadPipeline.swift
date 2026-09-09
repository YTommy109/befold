import Foundation

/// ファイルの静的な読み込み(存在確認・NormalizedTextCache 生成・チャンクセッション生成・全量読み込み)を
/// 行う純粋なロジック。ViewerStore の watcher・UserDefaults・onFileGone 等のオーケストレーションから
/// 独立しているため、QuickLook 拡張のような1回描画のみを必要とするホストからも再利用できる。
public enum ViewerLoadPipeline {
    /// チャンクリーダーの生成(ファイルを開いて先頭をプローブする)を行うファクトリ。
    /// バックグラウンドの読み込みタスクから呼ばれるため、アクター隔離しない。
    public typealias ChunkedReaderFactory = @Sendable (NormalizedTextCache, FileType) throws -> any ChunkedTextReading

    /// 既定のチャンクリーダー生成。GUI 本体(ViewerStore)・QuickLook 拡張(loadOneShot)・
    /// CLI(`--check`)がすべてこれを使う。ここが分岐すると「GUI では開けるのに --check が
    /// 開けないと言う」といったホスト間のドリフトになるため、生成規則は 1 箇所に置く。
    public static let defaultChunkedReaderFactory: ChunkedReaderFactory = { cache, fileType in
        StringChunkReader(cache: cache, boundary: ChunkBoundary(fileType: fileType))
    }

    /// 読み込んだ Data が PDF として開けるかの判定。
    ///
    /// **既定値を置かない。** 判定の実体は `PDFDocument(data:)` で、これは PDFKit を
    /// 要する(BefoldKit は Foundation だけで成立する層に保つ。TASK-598)。ここから
    /// 既定実装を参照できないため、デフォルト引数は方針ではなく**構造上置けない**。
    /// 結果として渡し忘れは必ずコンパイルエラーになり、ホストごとに判定が食い違う
    /// 経路が生まれない。実装は `BefoldPDFProbe.PDFDataProbe.isReadable`。
    ///
    /// バックグラウンドの読み込みタスクから呼ばれるため、アクター隔離しない。
    public typealias PDFReadabilityProbe = @Sendable (Data) -> Bool

    /// 1 回の読み込みの入力。
    ///
    /// 個別の引数で渡すと `load` の引数が 6 個になり `function_parameter_count` に
    /// 触れるが、束ねたのは数合わせではなく、これらが「1 回の読み込みの入力」という
    /// 1 つの関心だから(befold 側にあった `LoadInputs` を、判定 probe を加えて
    /// ここへ引き上げたもの。同じ束が 2 つあると片方だけに項目が増える)。
    ///
    /// `fileReader` と `contentLoader` を両方持つのは、後者が前者から作られる一方で
    /// `ViewerStore` が `ContentLoader` を使い回すため。**同じ `FileReading` から
    /// 作ること**——別々に渡すと、存在確認とデータ読み出しが違うファイル像を見る。
    public struct Inputs: Sendable {
        public let resolved: URL
        public let fileType: FileType
        public let fileReader: any FileReading
        public let contentLoader: ContentLoader
        public let chunkedReaderFactory: ChunkedReaderFactory
        /// PDF として開けるかの判定。既定値は構造上置けない(上の typealias を参照)。
        public let isPDFReadable: PDFReadabilityProbe

        public init(
            resolved: URL,
            fileType: FileType,
            fileReader: any FileReading,
            contentLoader: ContentLoader,
            chunkedReaderFactory: @escaping ChunkedReaderFactory,
            isPDFReadable: @escaping PDFReadabilityProbe
        ) {
            self.resolved = resolved
            self.fileType = fileType
            self.fileReader = fileReader
            self.contentLoader = contentLoader
            self.chunkedReaderFactory = chunkedReaderFactory
            self.isPDFReadable = isPDFReadable
        }

        /// `contentLoader` を同じ `fileReader` から作る簡便版。
        ///
        /// **既定はこちら。** 上の初期化子は `ViewerStore` のように `ContentLoader` を
        /// 窓の寿命にわたって使い回すホストのためにある。両者を別々に渡せる形だけを
        /// 残すと、存在確認(fileReader)とデータ読み出し(contentLoader)が違う
        /// `FileReading` を見る組み合わせが書けてしまい、コンパイルでは捕まらない。
        public init(
            resolved: URL,
            fileType: FileType,
            fileReader: any FileReading,
            chunkedReaderFactory: @escaping ChunkedReaderFactory,
            isPDFReadable: @escaping PDFReadabilityProbe
        ) {
            self.init(
                resolved: resolved,
                fileType: fileType,
                fileReader: fileReader,
                contentLoader: ContentLoader(fileReader: fileReader),
                chunkedReaderFactory: chunkedReaderFactory,
                isPDFReadable: isPDFReadable
            )
        }
    }

    /// 読み込みの結果。呼び出し側(ViewerStore)がメインアクターへ持ち帰って一括適用する。
    public enum Outcome: Sendable {
        /// ファイルが存在しない(削除グレース期間を開始する)。
        case missing
        /// 行指向ファイルのチャンクセッションを開始し、先頭チャンクを読み込んだ。
        case chunked(session: any ChunkedTextReading, cache: NormalizedTextCache, firstChunk: String, isAtEnd: Bool)
        /// 全量読み込みの結果(rejectReason を含みうる)。
        case full(ContentLoader.LoadedContent, cache: NormalizedTextCache?)
        /// バイナリを**生データのまま**読み込んだ結果(PDF)。base64 化しないのは
        /// `PDFView` が `Data` を直接受けられるため。画像は `data:` URI として JS へ
        /// 渡すので `.full`(base64)のままで、この case を通らない。
        case binary(ContentLoader.LoadedData)
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
        _ inputs: Inputs,
        oneShotLoad: Bool = false,
        embedLocalImages: Bool = true,
        imageEmbedder: MarkdownImageEmbedder = .shared
    ) async -> Outcome {
        guard inputs.fileReader.fileExists(at: inputs.resolved) else { return .missing }

        if inputs.fileType == .pdf {
            let loaded = inputs.contentLoader.loadData(from: inputs.resolved, computeHash: !oneShotLoad)
            return .binary(validated(loaded, isPDFReadable: inputs.isPDFReadable))
        }

        if inputs.fileType.isBinaryContent {
            // 同一内容スキップ用の hash は LoadedContent が運ぶ(バイナリは
            // NormalizedTextCache を作らないので cache: nil のまま)。oneShotLoad の扱いは
            // テキスト側(NormalizedTextCache)と同じ規則。
            let loaded = inputs.contentLoader.load(
                from: inputs.resolved, fileType: inputs.fileType, computeHash: !oneShotLoad
            )
            return .full(loaded, cache: nil)
        }

        // 拒否理由を binaryContent として区別するのは、ここに来るのが必ず
        // 「NUL を含み、BOM も UTF-16 のパリティも持たない」ファイルだから
        // (isBinary の判定条件)。汎用の unsupportedFormat に丸めると、
        // テキストのはずのファイルに NUL が混入した事故を追跡できない。
        if inputs.fileReader.isBinary(at: inputs.resolved) {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .binaryContent, content: ""),
                cache: nil
            )
        }

        let sizeLimit = inputs.fileType.isChunkable
            ? NormalizedTextCache.maxFileSizeBytes
            : nonChunkableSizeLimit(oneShotLoad: oneShotLoad)
        if let size = inputs.fileReader.fileSize(at: inputs.resolved), size > sizeLimit {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                cache: nil
            )
        }

        do {
            let data = try inputs.fileReader.readData(from: inputs.resolved)

            guard inputs.fileType.isChunkable else {
                return try loadFull(data: data, fileType: inputs.fileType, oneShotLoad: oneShotLoad)
            }
            return try await loadChunked(
                inputs, data: data, oneShotLoad: oneShotLoad,
                embedLocalImages: embedLocalImages, imageEmbedder: imageEmbedder
            )
        } catch {
            if !inputs.fileReader.fileExists(at: inputs.resolved) { return .missing }
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

    /// PDF として開けないデータを拒否理由へ落とす。
    ///
    /// 読み込み自体は成功しているため、ここで見なければ `rejectReason` は nil のまま
    /// `PDFView` が黙って空白を出す(バナーも出ない)。判定は注入された probe に委ね、
    /// 表示側が `PDFDocument` を作る条件と 1 つの事実を共有する。
    private static func validated(
        _ loaded: ContentLoader.LoadedData, isPDFReadable: PDFReadabilityProbe
    ) -> ContentLoader.LoadedData {
        guard let data = loaded.data, !isPDFReadable(data) else { return loaded }
        return ContentLoader.LoadedData(rejectReason: .damagedDocument, data: nil)
    }

    /// チャンク読み込み経路。先頭チャンクだけを描いて残りは追記で足す。
    ///
    /// 先頭チャンクを読んだ時点で「打ち切ったままでは表示できない」と分かったものは、
    /// ここで全量読み込みへ切り替える(`needsWholeDocument` を参照)。
    private static func loadChunked(
        _ inputs: Inputs, data: Data, oneShotLoad: Bool,
        embedLocalImages: Bool, imageEmbedder: MarkdownImageEmbedder
    ) async throws -> Outcome {
        // 先頭チャンク描画に必要な範囲だけを正規化・行分割する
        // (ファイル全体を materialize しない。100MB 級ファイルでの
        // ピークメモリ・CPU 削減のため。詳細は NormalizedTextCache 参照)。
        let cache = try NormalizedTextCache(data: data, normalizeFully: false, oneShotLoad: oneShotLoad)
        let reader = try inputs.chunkedReaderFactory(cache, inputs.fileType)
        let firstChunk = try await reader.readNextChunk()
        let truncatesTransformable = !firstChunk.isAtEnd && needsWholeDocument(
            inputs, prolog: firstChunk.text, byteCount: data.count, oneShotLoad: oneShotLoad
        )
        if truncatesTransformable {
            return try loadFull(data: data, fileType: inputs.fileType, oneShotLoad: oneShotLoad)
        }
        if embedLocalImages, inputs.fileType == .markdown {
            // markdown もチャンク読み込みの対象になったため(Issue #307)、
            // ウォームアップは先頭チャンクに対して行う。後続チャンクの画像は
            // 追記時(applyAppend)に埋め込まれる。
            // render 経路と同じキャッシュを温めるため、同一インスタンス(本番は .shared)を経由すること。
            _ = imageEmbedder.embedLocalImages(in: firstChunk.text, baseURL: inputs.resolved)
        }
        return .chunked(
            session: reader, cache: cache,
            firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
        )
    }

    /// 打ち切ったままでは表示できず、全量読み込みへ切り替えるべきかどうか(TASK-608)。
    ///
    /// XSLT 変換表示は文書全体を 1 つの構造として扱うため、先頭チャンクだけでは
    /// 必ずパースエラーになる。実際 `ViewerScriptDispatcher` / `OneShotRenderer` は
    /// `allowsXSLT: !truncation.isTruncated` を渡して変換を止めており、
    /// 1000 行(`StringChunkReader.linesPerChunk`)を超える XML は XSL があっても
    /// ソース表示に落ちていた(実測: e-Gov 法令XMLは最小の日本国憲法 1,476 行でも
    /// 該当し、この経路を一度も通らない)。
    ///
    /// 直すのは「打ち切った断片を変換する」側ではなく「変換対象を打ち切る」側。
    /// 判定をここに置くのは、`FileType.isChunkable` がファイルを見られないため
    /// (XSL の有無は拡張子から決まらない。TASK-596 と同じ理由)。
    ///
    /// 全量読み込みに切り替えると上限が `NormalizedTextCache.maxFileSizeBytes`(100MB)から
    /// `nonChunkableSizeLimit`(本体 10MB / QuickLook 2MB)へ下がるため、超えるものは
    /// 切り替えず従来どおりチャンク読み込みで段階描画する —— 変換はできないが、
    /// `fileTooLarge` の空表示よりソースが読めるほうがよい。
    ///
    /// - Parameter prolog: 先頭チャンク。`<?xml-stylesheet?>` はプロローグにしか
    ///   置けないため、全文と同じ答えが出る。
    private static func needsWholeDocument(
        _ inputs: Inputs, prolog: String, byteCount: Int, oneShotLoad: Bool
    ) -> Bool {
        guard inputs.fileType == .xml, byteCount <= nonChunkableSizeLimit(oneShotLoad: oneShotLoad) else {
            return false
        }
        return XSLStylesheetResolver.resolve(
            xml: prolog, fileURL: inputs.resolved, fileReader: inputs.fileReader
        ) != nil
    }

    /// チャンク読み込みできない形式(mmd/svg/html)のサイズ上限。
    /// 静的1回描画ホスト(QuickLook 拡張)ではより厳しい上限を使う。
    /// これらは全量を一括で DOM 化するため、WebContent のメモリと描画時間が
    /// サイズにほぼ比例して伸びる(詳細は定数側のコメント)。
    static func nonChunkableSizeLimit(oneShotLoad: Bool) -> Int {
        oneShotLoad
            ? ContentLoader.maxOneShotTextFileSizeBytes
            : ContentLoader.maxTextFileSizeBytes
    }

    /// チャンク非対応(mmd/svg/html)の全量読み込み。
    /// 画像埋め込みのウォームアップはチャンク経路(markdown)側で行うため、ここでは不要。
    private static func loadFull(data: Data, fileType: FileType, oneShotLoad: Bool) throws -> Outcome {
        let cache = try NormalizedTextCache(data: data, oneShotLoad: oneShotLoad)
        if cache.text.utf8.count > nonChunkableSizeLimit(oneShotLoad: oneShotLoad) {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                cache: nil
            )
        }
        let hasDeclaredHTMLCharset = fileType == .html ? HTMLCharsetNormalizer.hasCharsetDeclaration(data) : nil
        return .full(
            ContentLoader.LoadedContent(
                rejectReason: nil, content: cache.text, hasDeclaredHTMLCharset: hasDeclaredHTMLCharset
            ),
            cache: cache
        )
    }
}
