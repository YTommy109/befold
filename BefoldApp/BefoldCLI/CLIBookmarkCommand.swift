import Foundation

/// `befold --bookmark <path>` — 既存の BookmarkStore を再利用してブックマークを追加する。
public enum CLIBookmarkCommand {
    @MainActor
    public static func run(
        _ path: String,
        addBookmark: @MainActor (URL) -> Void,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> CLICommandResult {
        guard fileExists(path) else {
            return CLICommandResult(message: "No such path: \(path)", exitCode: 1)
        }
        let url = URL(fileURLWithPath: path)
        addBookmark(url)
        return CLICommandResult(message: "Bookmarked: \(url.path)", exitCode: 0)
    }
}
