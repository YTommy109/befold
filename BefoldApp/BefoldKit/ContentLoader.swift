import Foundation

/// ファイルの種別とサイズから読み込み結果を決定する純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
public struct ContentLoader: Sendable {
    /// 全量読み込みとバイナリ表示の共通上限(50MB)。
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

    /// 指定 URL のファイルを種別に応じて読み込み、表示可否と内容を返す。
    public func load(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        let sizeLimit = fileType.isBinaryContent ? Self.maxFileSizeBytes : Self.maxTextFileSizeBytes
        if let size = fileReader.fileSize(at: resolved), size > sizeLimit {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        } else if fileType.isBinaryContent {
            if let data = try? fileReader.readData(from: resolved) {
                return LoadedContent(rejectReason: nil, content: data.base64EncodedString())
            } else {
                return LoadedContent(rejectReason: .unsupportedFormat, content: "")
            }
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(rejectReason: .unsupportedFormat, content: "")
        } else {
            do {
                let text = try fileReader.readString(from: resolved)
                return LoadedContent(rejectReason: nil, content: text)
            } catch {
                return LoadedContent(rejectReason: .unsupportedFormat, content: "")
            }
        }
    }
}
