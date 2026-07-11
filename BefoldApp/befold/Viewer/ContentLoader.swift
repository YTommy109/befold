import Foundation

/// ファイルの種別とサイズから読み込み結果を決定する純粋なロジック。
/// ViewerStore から読み込み処理を切り出し、単体テスト可能にする。
struct ContentLoader: Sendable {
    /// メインアクター上で同期読み込みを許容する最大ファイルサイズ(10MB)。
    /// これを超えるファイルは読み込まず、非対応扱いにしてビーチボール化を防ぐ。
    static let maxFileSizeBytes = 10 * 1024 * 1024

    /// 画像・PDF(バイナリ表示対象)の最大ファイルサイズ(50MB)。
    /// スキャン PDF や高解像度写真は 10MB を超えることが珍しくないため
    /// テキストより緩くする。base64 化で約 1.33 倍に膨らんで
    /// evaluateJavaScript を通るため、無制限にはしない。
    static let maxBinaryFileSizeBytes = 50 * 1024 * 1024

    struct LoadedContent: Sendable, Equatable {
        let isUnsupported: Bool
        let content: String
    }

    private let fileReader: any FileReading

    init(fileReader: any FileReading = DefaultFileReader()) {
        self.fileReader = fileReader
    }

    func load(from url: URL, fileType: FileType) -> LoadedContent {
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
