import BefoldKit
import Foundation

/// CLI サブコマンドの実行結果。`exitCode == 0` なら stdout、それ以外は stderr へ `message` を出力する。
struct CLICommandResult: Equatable {
    let message: String
    let exitCode: Int32
}

/// `befold bookmark add <path>` — 既存の BookmarkStore を再利用してブックマークを追加する。
enum CLIBookmarkCommand {
    @MainActor
    static func run(
        _ arguments: [String],
        bookmarkStore: BookmarkStore = BookmarkStore(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> CLICommandResult {
        guard arguments.count == 2, arguments[0] == "add" else {
            return CLICommandResult(message: "使い方: befold bookmark add <path>", exitCode: 64)
        }
        let path = arguments[1]
        guard fileExists(path) else {
            return CLICommandResult(message: "指定されたパスが見つかりません: \(path)", exitCode: 1)
        }
        let url = URL(fileURLWithPath: path)
        bookmarkStore.add(url)
        return CLICommandResult(message: "ブックマークに追加しました: \(url.path)", exitCode: 0)
    }
}

/// `befold check <path>` — 既存の FileType・サイズ上限定数を再利用し、befold が開けるファイルかどうかを判定する。
enum CLICheckCommand {
    static func run(_ arguments: [String], fileReader: any FileReading = DefaultFileReader()) -> CLICommandResult {
        guard arguments.count == 1 else {
            return CLICommandResult(message: "使い方: befold check <path>", exitCode: 64)
        }
        let path = arguments[0]
        let url = URL(fileURLWithPath: path)
        guard fileReader.fileExists(at: url) else {
            return CLICommandResult(message: "指定されたパスが見つかりません: \(path)", exitCode: 1)
        }

        guard let target = DirectoryLister.resolveFileToOpen(at: url, fileReader: fileReader) else {
            return CLICommandResult(message: "フォルダー内にファイルがありません: \(path)", exitCode: 1)
        }

        // フォルダーは非空だが、解決先が実体のないエントリ(削除済みターゲットを指す
        // ダングリングシンボリックリンク等)のケース。「フォルダーが空」とは区別して報告する。
        guard fileReader.isExistingFile(at: target) else {
            return CLICommandResult(
                message: "開けません: \(target.path)\n理由: ファイルの実体が見つかりません(壊れたシンボリックリンクの可能性があります)",
                exitCode: 1
            )
        }

        let fileType = FileType(url: target)
        let size = fileReader.fileSize(at: target) ?? 0
        let detail = "サイズ: \(size)バイト\n型: \(fileType.jsValue)(拡張子: .\(target.pathExtension))"

        if let reason = rejectReason(for: fileType, size: size, target: target, fileReader: fileReader) {
            return CLICommandResult(
                message: "開けません: \(target.path)\n理由: \(reason.localizedMessage)\n\(detail)", exitCode: 1
            )
        }
        return CLICommandResult(message: "開けます: \(target.path)\n\(detail)", exitCode: 0)
    }

    /// ContentLoader/NormalizedTextCache のサイズ上限定数を再利用し、開けない理由があれば返す。
    /// 実際のオープン経路 ViewerLoadPipeline.load と同じ順序(バイナリ判定 → サイズ判定)で
    /// 判定する。順序が逆だと、10MB超かつ内容がバイナリ判定されるテキスト系ファイルで
    /// fileTooLarge/unsupportedFormat の報告が実際のオープン結果と食い違う。
    private static func rejectReason(
        for fileType: FileType, size: Int, target: URL, fileReader: any FileReading
    ) -> RejectReason? {
        if fileType.isBinaryContent {
            return size > ContentLoader.maxFileSizeBytes ? .fileTooLarge : nil
        }
        if fileReader.isBinary(at: target) {
            return .unsupportedFormat
        }
        let sizeLimit = fileType.isLineOriented
            ? NormalizedTextCache.maxFileSizeBytes
            : ContentLoader.maxTextFileSizeBytes
        return size > sizeLimit ? .fileTooLarge : nil
    }
}
