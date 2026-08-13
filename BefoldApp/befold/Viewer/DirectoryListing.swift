import Foundation

/// ディレクトリ 1 回の列挙結果。**行に畳む前の材料**であって、行配列ではない。
///
/// 列挙結果を畳んだ配列として返すと、そこへ展開を足す側が
/// `depth == 0` で分解し直して材料へ戻す往復が要る。
/// 実際にそうなっていて、1 回の列挙で行の組み立てが 2 回走っていた(TASK-442.1)。
/// 材料のまま持ち回れば、畳むのは 1 回で済み、分解する経路がそもそも作れない。
struct DirectoryListing: Sendable, Equatable {
    /// ルート直下の行(親移動行を含まない)。並びは `DirectoryLister.childEntries` が確定させる。
    var rootChildren: [FileListEntry]
    /// 列挙に失敗したか。true のとき `rootChildren` は「そのフォルダの中身」ではない。
    ///
    /// **行の有無で失敗を判定してはならない**(TASK-410)。失敗しても
    /// 「いま開いている文書」の行は出す必要があり、`rootChildren` が空でないことは
    /// 列挙が成功したことを意味しない。逆に空でも「読めて、中身が空だった」場合がある。
    /// 材料を加工する `appendingOpenFile` はこの事実を書き写して運ぶ。
    var didFailEnumeration: Bool = false

    static let empty = DirectoryListing(rootChildren: [])

    /// 材料を行の配列へ畳む。
    ///
    /// **`SidebarRowBuilder.rows` を呼ぶプロダクトコード上の唯一の場所。**
    /// ここ以外から呼ぶと、同じ列挙結果に対して組み立てが 2 回走る形へ戻る
    /// (`SidebarRowAssemblySingleSourceTests` がソース走査でこれを縛っている)。
    ///
    /// 引数を省くと「展開なし」の縮退形になり、全行 depth 0・開閉三角なしの
    /// ドリルダウン表示と同じ出力になる。
    func rows(
        material: SidebarRowBuilder.Material = .init(), showsDisclosure: Bool = false
    ) -> [FileListEntry] {
        SidebarRowBuilder.rows(
            rootChildren: rootChildren,
            expanded: material.expanded,
            childrenByPathKey: material.childrenByPathKey,
            loading: material.loading,
            failed: material.failed,
            showsDisclosure: showsDisclosure
        )
    }

    /// 開いているファイルが一覧に無ければ足す(規則は `DirectoryLister.appendingOpenFile`)。
    ///
    /// 追記先は `rootChildren` の末尾で、これは畳んだあとの配列の末尾と一致する。
    /// 深さ優先で畳んだ配列の末尾は「最後のルート直下行とその配下すべての直後」であり、
    /// そこは配下を持たない新しいルート直下行が入る位置そのものだから。
    ///
    /// **`didFailEnumeration` はそのまま持ち越す。** 開いている文書の行を足したことで
    /// 「読めた」ことにはならない(TASK-410)。
    func appendingOpenFile(_ openFile: URL?, in directory: URL) -> DirectoryListing {
        DirectoryListing(
            rootChildren: DirectoryLister.appendingOpenFile(
                openFile, to: rootChildren, in: directory
            ),
            didFailEnumeration: didFailEnumeration
        )
    }
}
