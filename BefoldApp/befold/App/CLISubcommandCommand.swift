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

        let target: URL
        if fileReader.isDirectory(at: url) {
            guard let resolved = resolveFileInDirectory(url, fileReader: fileReader) else {
                return CLICommandResult(message: "フォルダー内に開けるファイルがありません: \(path)", exitCode: 1)
            }
            target = resolved
        } else {
            target = url
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

    /// フォルダー内の最初に開けるファイルを探す。既存の DirectoryLister.resolveFileToOpen と
    /// 同じ優先順位(対応形式優先→先頭ファイル)だが、fileReader を注入できるようテスト用に簡略化している。
    private static func resolveFileInDirectory(_ directory: URL, fileReader: any FileReading) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        let files = entries.filter { fileReader.isExistingFile(at: $0) }.sorted { $0.path < $1.path }
        return files.first { FileType.isSupported($0) } ?? files.first
    }

    /// ContentLoader/NormalizedTextCache のサイズ上限定数を再利用し、開けない理由があれば返す。
    private static func rejectReason(
        for fileType: FileType, size: Int, target: URL, fileReader: any FileReading
    ) -> RejectReason? {
        let sizeLimit = fileType.isBinaryContent
            ? ContentLoader.maxFileSizeBytes
            : fileType.isLineOriented ? NormalizedTextCache.maxFileSizeBytes : ContentLoader.maxTextFileSizeBytes
        if size > sizeLimit {
            return .fileTooLarge
        }
        if !fileType.isBinaryContent, fileReader.isBinary(at: target) {
            return .unsupportedFormat
        }
        return nil
    }
}
