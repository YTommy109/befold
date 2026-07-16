import Foundation

/// バイナリファイル(画像/PDF)をサイズ判定つきで読み込む純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
public struct ContentLoader: Sendable {
    /// バイナリ表示の上限(50MB)。
    public static let maxFileSizeBytes = 50 * 1024 * 1024

    /// 非行指向テキスト(Markdown/Mermaid/HTML/SVG)の上限。
    public static let maxTextFileSizeBytes = 10 * 1024 * 1024

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
