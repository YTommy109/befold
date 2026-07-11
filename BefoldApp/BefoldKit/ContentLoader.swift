import Foundation

/// ファイルの種別とサイズから読み込み結果を決定する純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
public struct ContentLoader: Sendable {
    /// メインアクター上で同期読み込みを許容する最大ファイルサイズ(10MB)。
    /// これを超えるファイルは読み込まず、非対応扱いにしてビーチボール化を防ぐ。
    public static let maxFileSizeBytes = 10 * 1024 * 1024

    /// 画像・PDF(バイナリ表示対象)の最大ファイルサイズ(50MB)。
    /// スキャン PDF や高解像度写真は 10MB を超えることが珍しくないため
    /// テキストより緩くする。base64 化で約 1.33 倍に膨らんで
    /// evaluateJavaScript を通るため、無制限にはしない。
    public static let maxBinaryFileSizeBytes = 50 * 1024 * 1024

    /// ファイル読み込みの結果。表示可否と表示内容を保持する。
    public struct LoadedContent: Sendable, Equatable {
        public let isUnsupported: Bool
        public let content: String

        public init(isUnsupported: Bool, content: String) {
            self.isUnsupported = isUnsupported
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
        let sizeLimit = fileType.isBinaryContent ? Self.maxBinaryFileSizeBytes : Self.maxFileSizeBytes
        if let size = fileReader.fileSize(at: resolved), size > sizeLimit {
            return LoadedContent(isUnsupported: true, content: "")
        } else if fileType.isBinaryContent {
            if let data = try? fileReader.readData(from: resolved) {
                return LoadedContent(isUnsupported: false, content: data.base64EncodedString())
            } else {
                return LoadedContent(isUnsupported: true, content: "")
            }
        } else if fileReader.isBinary(at: resolved) {
            return LoadedContent(isUnsupported: true, content: "")
        } else {
            return LoadedContent(isUnsupported: false, content: (try? fileReader.readString(from: resolved)) ?? "")
        }
    }
}
