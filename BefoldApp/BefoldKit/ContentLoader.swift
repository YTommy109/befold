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

        public init(rejectReason: RejectReason?, content: String) {
            self.rejectReason = rejectReason
            self.content = content
        }
    }

    private let fileReader: any FileReading

    public init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    /// 指定 URL のバイナリファイルを読み込み、表示可否と base64 内容を返す。
    public func load(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        }
        if let data = try? fileReader.readData(from: resolved) {
            return LoadedContent(rejectReason: nil, content: data.base64EncodedString())
        }
        return LoadedContent(rejectReason: .unsupportedFormat, content: "")
    }
}
