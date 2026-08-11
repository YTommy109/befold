@testable import befold
import Foundation

/// テスト専用の書き味。`DirectoryListing` は本番では
/// 「行 + 列挙に失敗したか」を必ず両方決めさせる形にしてあり(TASK-410)、
/// そこへ既定値を持ち込まないためにここへ置く。
///
/// テストの大半は「読めた結果としてこの行が並ぶ」を書きたいだけなので、
/// 配列リテラルをそのまま渡せるようにする。**失敗側は書けない**ので、
/// 失敗を測るテストは `DirectoryListing(entries:didFailEnumeration:)` を明示的に使う
/// ことになり、どちらを測っているかがコード上で必ず見分けられる。
extension DirectoryListing: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FileListEntry...) {
        self.init(entries: elements, didFailEnumeration: false)
    }
}

extension DirectoryListing {
    /// 読めた結果としての一覧。行を変数で持っているテスト向け。
    init(rows: [FileListEntry]) {
        self.init(entries: rows, didFailEnumeration: false)
    }

    /// 読めなかった一覧。行は通常空だが、開いている文書の行が足されることがある
    /// (`DirectoryLister.appendingOpenFile`)ため、行を渡せる形にしておく。
    static func failed(rows: [FileListEntry] = []) -> DirectoryListing {
        DirectoryListing(entries: rows, didFailEnumeration: true)
    }
}

extension DirectoryLister {
    /// テスト用: 行だけを見る呼び出しの入口。列挙の成否まで見るテストは
    /// `listEntries` をそのまま呼び、`didFailEnumeration` を確かめること。
    static func listEntryRows(
        in directory: URL, sortOrder: befold.SortOrder, showHiddenFiles: Bool = false,
        home: URL = defaultHome
    ) -> [FileListEntry] {
        listEntries(
            in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles, home: home
        ).entries
    }
}
