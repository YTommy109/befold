import BefoldKit
import Foundation

/// `befold --bookmark <path>` — 既存の BookmarkStore を再利用してブックマークを追加する。
public enum CLIBookmarkCommand {
    /// `addBookmark` は追加できたかどうかを返す。起動中の GUI へ転送する経路では
    /// 転送不達が失敗になるため、成功を報告してから何も残らないことがないよう結果を伝播する。
    @MainActor
    public static func run(
        _ path: String,
        addBookmark: @MainActor (URL) async -> Bool,
        fileReader: any FileReading = DefaultFileReader()
    ) async -> CLICommandResult {
        let url = URL(fileURLWithPath: path)
        guard fileReader.fileExists(at: url) else {
            return CLICommandResult(message: "No such path: \(path)", exitCode: 1)
        }
        // 起動中の GUI へ転送する前に弾く(転送先はパスを判定しない)。
        guard BookmarkStore.canBookmark(url, fileReader: fileReader) else {
            return CLICommandResult(message: "Folders cannot be bookmarked: \(path)", exitCode: 1)
        }
        guard await addBookmark(url) else {
            return CLICommandResult(
                message: "Failed to forward the bookmark to the running instance: \(url.path)", exitCode: 1
            )
        }
        return CLICommandResult(message: "Bookmarked: \(url.path)", exitCode: 0)
    }
}
