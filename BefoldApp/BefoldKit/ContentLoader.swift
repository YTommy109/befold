import CryptoKit
import Foundation

/// バイナリファイル(画像/PDF)をサイズ判定つきで読み込む純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
public struct ContentLoader: Sendable {
    /// バイナリ表示の上限(50MB)。
    public static let maxFileSizeBytes = 50 * 1024 * 1024

    /// 非行指向テキスト(Markdown/Mermaid/HTML/SVG)の上限。
    public static let maxTextFileSizeBytes = 10 * 1024 * 1024

    /// 静的1回描画ホスト(QuickLook 拡張)での非行指向テキストの上限。
    ///
    /// 非行指向はチャンク読み込みが効かず全量を DOM 化するため、WebContent プロセスの
    /// メモリがファイルサイズにほぼ比例して伸びる。実測(TASK-72.6 / macOS 26.5.2)では
    /// 1MB→901MB、2MB→1.57GB、4MB→2.24GB、9MB→4.17GB で、4MB 以上は描画が
    /// 3 秒以内に終わらず、プレビューが長時間空白のままになる。
    /// ユーザーが「表示されない」と誤解しない範囲として 2MB を上限にする。
    /// 行指向(CSV/コード)は先頭チャンクしか描画しないため 99MB でも 0.33 秒・
    /// WebContent 118MB に収まっており、この制限は不要。
    public static let maxOneShotTextFileSizeBytes = 2 * 1024 * 1024

    /// ファイル読み込みの結果。表示可否と表示内容を保持する。
    public struct LoadedContent: Sendable, Equatable {
        public let rejectReason: RejectReason?
        public let content: String
        /// 同一内容スキップ(ライブリロードで内容が変わっていないときに再描画しない)の
        /// 比較に使う hash。テキスト側の `NormalizedTextCache.dataHash` と同じ役割・同じ
        /// 作り方(生データの SHA256 先頭 8 バイト)で、比較してよい値かどうかも同じ規則に従う。
        ///
        /// **読み込みに成功したときだけ non-nil にすること。** `isUnchanged` は hash と
        /// fileType しか見ないため(`ViewerContentState`)、拒否理由が違うだけで content が
        /// どちらも空の読み込み同士に同じ hash を与えると、`rejectReason` の変化が
        /// 握り潰されてバナーの文言が事実と食い違う。この不変条件は
        /// `ContentLoaderTests` の拒否経路のケースが破れたら落ちる形で押さえてある。
        public let contentHash: Int?
        /// HTML の charset 宣言(BOM/meta charset)有無。fileType が .html かつ
        /// 全量読込に成功した場合のみ non-nil。それ以外は常に nil。
        public let hasDeclaredHTMLCharset: Bool?

        public init(
            rejectReason: RejectReason?, content: String, hasDeclaredHTMLCharset: Bool? = nil,
            contentHash: Int? = nil
        ) {
            self.rejectReason = rejectReason
            self.content = content
            self.contentHash = contentHash
            self.hasDeclaredHTMLCharset = hasDeclaredHTMLCharset
        }
    }

    private let fileReader: any FileReading

    public init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    /// 指定 URL のバイナリファイルを読み込み、表示可否と base64 内容を返す。
    ///
    /// computeHash: 同一内容スキップ用の `contentHash` を計算するかどうか。
    /// ライブリロードを行わない 1 回描画ホスト(QuickLook 拡張・CLI の `--check`)は
    /// この値を読まないため false を渡し、50MB のバイナリに対する SHA256 を払わない
    /// (テキスト側で `NormalizedTextCache(oneShotLoad:)` が同じ理由で hash を省くのと同じ規則)。
    /// **デフォルト引数を付けないこと。** 渡し忘れがコンパイルエラーにならなくなると、
    /// 1 回描画ホストが静かに hash を計算し続ける形の食い違いが起きる。
    public func load(from url: URL, fileType: FileType, computeHash: Bool) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        }
        if let data = try? fileReader.readData(from: resolved) {
            // hash は base64 化する前の生データから取る(base64 は約 1.33 倍に膨らむため)。
            return LoadedContent(
                rejectReason: nil, content: data.base64EncodedString(),
                contentHash: computeHash ? Self.hash(of: data) : nil
            )
        }
        return LoadedContent(rejectReason: .unsupportedFormat, content: "")
    }

    /// 同一内容スキップ用の hash。`NormalizedTextCache` と同じ作り方に揃える
    /// (同じ役割の値が 2 通りの作られ方をしないようにするため)。
    private static func hash(of data: Data) -> Int {
        SHA256.hash(data: data).withUnsafeBytes { buffer in
            buffer.load(as: Int.self)
        }
    }
}
