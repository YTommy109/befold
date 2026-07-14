import Foundation

/// ファイルの種別とサイズから読み込み結果を決定する純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
public struct ContentLoader: Sendable {
    /// 全量読み込みとバイナリ表示の共通上限(50MB)。
    public static let maxFileSizeBytes = 50 * 1024 * 1024

    /// プレビュー読み込みの上限(10MB)。これ以下なら同期全量読み込みで済む。
    public static let previewSizeBytes = 10 * 1024 * 1024

    /// ファイル読み込みの結果。表示可否と表示内容を保持する。
    public struct LoadedContent: Sendable, Equatable {
        public let rejectReason: RejectReason?
        public let content: String
        public let isTruncated: Bool

        public init(rejectReason: RejectReason?, content: String, isTruncated: Bool = false) {
            self.rejectReason = rejectReason
            self.content = content
            self.isTruncated = isTruncated
        }
    }

    private let fileReader: any FileReading

    public init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    /// 指定 URL のファイルを種別に応じて読み込み、表示可否と内容を返す。
    public func load(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
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
            return LoadedContent(
                rejectReason: nil,
                content: (try? fileReader.readString(from: resolved)) ?? ""
            )
        }
    }

    /// previewSizeBytes を超えるテキストファイルは先頭のみ読み込み、isTruncated を立てる。
    public func loadPreview(from url: URL, fileType: FileType) -> LoadedContent {
        let resolved = url.resolvingSymlinksInPath()
        if let size = fileReader.fileSize(at: resolved), size > Self.maxFileSizeBytes {
            return LoadedContent(rejectReason: .fileTooLarge, content: "")
        } else if fileType.isBinaryContent {
            return load(from: url, fileType: fileType)
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(rejectReason: .unsupportedFormat, content: "")
        } else {
            let content = (try? fileReader.readString(from: resolved, maxBytes: Self.previewSizeBytes)) ?? ""
            return LoadedContent(rejectReason: nil, content: content, isTruncated: true)
        }
    }
}
