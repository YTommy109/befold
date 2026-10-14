import Foundation

/// フォルダー一覧(`FolderListingView`)の行に添える変更日・サイズ・種類。
///
/// `FileListEntry` には載せない。その型と `DirectoryLister` の列挙はサイドバーと共有で、
/// ここへ載せるとサイドバーまで全ファイルの stat を払う(TASK-707)。一覧が出たあとに
/// MainActor の外で取得し、届くまでの行は名前だけで描く。
struct FolderListingMetadata: Equatable, Sendable {
    let modified: Date?
    /// フォルダーは nil(Finder と同じく空欄。配下の再帰集計は巨大フォルダーで重い)。
    let size: Int64?
    /// Finder と同じ `localizedTypeDescription`(OS が翻訳する)。
    let kind: String?

    private static let keys: Set<URLResourceKey> = [
        .contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey,
    ]

    /// 呼び出し元アクターを離れて取得する。読めない行は辞書に載せない。
    static func load(for urls: [URL]) async -> [URL: FolderListingMetadata] {
        // 種類の説明は拡張子が同じなら同じ。LaunchServices への問い合わせを拡張子ごとに 1 回にする。
        var kindByExtension: [String: String] = [:]
        var result: [URL: FolderListingMetadata] = [:]
        result.reserveCapacity(urls.count)
        for original in urls {
            // URL は読んだ resourceValues を自分で覚える。行が持ち回る同じ URL で取り直すと
            // 更新前のサイズ・日付が返るので、毎回捨ててから読む(再取得で行を更新するため)。
            var url = original
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isDirectory = values.isDirectory == true
            let ext = url.pathExtension.lowercased()
            var kind = values.localizedTypeDescription
            if !isDirectory, !ext.isEmpty {
                if let cached = kindByExtension[ext] {
                    kind = cached
                } else if let kind {
                    kindByExtension[ext] = kind
                }
            }
            result[original] = FolderListingMetadata(
                modified: values.contentModificationDate,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                kind: kind
            )
        }
        return result
    }
}
