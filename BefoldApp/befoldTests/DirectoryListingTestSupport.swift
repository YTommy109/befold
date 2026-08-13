@testable import befold
import Foundation

/// テスト専用の書き味。列挙の成否(`didFailEnumeration`)は本番では必ず決めさせる形に
/// してあり(TASK-410)、そこへ既定値を持ち込まないためにここへ置く。
///
/// テストの大半は「読めた結果としてこの行が並ぶ」を書きたいだけなので、配列リテラルを
/// そのまま渡せるようにする。**失敗側は書けない**ので、失敗を測るテストは `failed(rows:)`
/// か `didFailEnumeration:` の明示指定を使うことになり、どちらを測っているかが
/// コード上で必ず見分けられる。
///
/// 型が 2 つあるのは、行に畳む前の材料(`DirectoryListing` / TASK-442.1)と、
/// プレビューへ渡す畳んだ行(`SharedFolderListing`)が別物だから。
extension SharedFolderListing: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FileListEntry...) {
        self.init(entries: elements, didFailEnumeration: false)
    }
}

extension SharedFolderListing {
    /// 読めた結果としての一覧。行を変数で持っているテスト向け。
    init(rows: [FileListEntry]) {
        self.init(entries: rows, didFailEnumeration: false)
    }

    /// 読めなかった一覧。行は通常空だが、開いている文書の行が足されることがある
    /// (`DirectoryLister.appendingOpenFile`)ため、行を渡せる形にしておく。
    static func failed(rows: [FileListEntry] = []) -> SharedFolderListing {
        SharedFolderListing(entries: rows, didFailEnumeration: true)
    }
}

extension DirectoryListing: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FileListEntry...) {
        self.init(rootChildren: elements, didFailEnumeration: false)
    }
}

extension DirectoryListing {
    /// 読めた結果としての材料。ルート直下の行だけを持たせる(親移動行は無し)。
    init(rows: [FileListEntry]) {
        self.init(rootChildren: rows, didFailEnumeration: false)
    }

    /// 読めなかった材料。
    static func failed(rows: [FileListEntry] = []) -> DirectoryListing {
        DirectoryListing(rootChildren: rows, didFailEnumeration: true)
    }
}

extension DirectoryLister {
    /// テスト用: 行だけを見る呼び出しの入口。列挙の成否まで見るテストは
    /// `listing` をそのまま呼び、`didFailEnumeration` を確かめること。
    static func listEntryRows(
        in directory: URL, sortOrder: befold.SortOrder, showHiddenFiles: Bool = false
    ) -> [FileListEntry] {
        listing(in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles).rows()
    }
}
