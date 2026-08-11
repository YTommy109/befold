import Foundation

/// ルート一覧の取得結果。行の配列だけでは「読めて、中身が空だった」と「読めなかった」が
/// 同じ空配列になるため、失敗した事実を別に運ぶ(TASK-410)。
///
/// 行を Optional (`[FileListEntry]?`) にはしない。失敗しても親移動行と、いま開いている
/// 文書の行(`DirectoryLister.appendingOpenFile`)は出す必要があり、nil にするとその経路ごと
/// 落ちる。「開いている文書は必ず一覧に含める」は列挙の成否に関わらず保たれる不変条件で、
/// 失敗の伝達がそれを迂回してはならない。
struct DirectoryListing: Equatable, Sendable {
    /// 表示する行。失敗時でも親移動行・開いている文書の行が入りうるため、
    /// **空かどうかで失敗を判定してはならない**(`didFailEnumeration` を見ること)。
    let entries: [FileListEntry]
    /// 列挙に失敗したか。true のとき `entries` は「そのフォルダの中身」ではない。
    let didFailEnumeration: Bool

    /// 行を差し替え、失敗の事実は保つ。行を加工する経路(`appendingOpenFile` など)が
    /// `DirectoryListing` を組み直す唯一の口にして、加工のたびに `didFailEnumeration` を
    /// 書き写す(= 書き忘れて false へ戻る)形にしない。
    func replacingEntries(_ newEntries: [FileListEntry]) -> DirectoryListing {
        DirectoryListing(entries: newEntries, didFailEnumeration: didFailEnumeration)
    }

    /// 行を絞り込む。`replacingEntries` と同じく失敗の事実は保つ。
    func filteringEntries(_ isIncluded: (FileListEntry) -> Bool) -> DirectoryListing {
        replacingEntries(entries.filter(isIncluded))
    }
}
