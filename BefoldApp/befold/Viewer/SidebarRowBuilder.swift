import Foundation

/// サイドバーの行配列を組み立てる単一の実装元。
///
/// 入力は「親移動行 + ルート直下の行 + 展開済みフォルダの集合 + 各フォルダ直下の行」で、
/// 出力は depth を持つ **フラットな** 行配列。ドリルダウン表示はこの縮退形
/// (展開集合が空)として同じ関数を通る。
///
/// フラットな 1 本の配列を保つのは、`FileListModel.selectedRow()` の
/// 「visibleEntries の添字 = NSTableView の行番号」という不変条件を守るため。
/// `OutlineGroup` へ移すとこの対応が切れ、スクロール追従とキーボード移動の
/// 両方が添字前提のまま壊れる。
///
/// **材料(childrenByPathKey)をクロージャではなく辞書で受ける**のが要点。
/// 子の列挙は `FileManager` 走査と `DirectoryLister.containsSupportedFile(in:)`
/// (フォルダ 1 件ごとにディレクトリ列挙)を伴う。クロージャで受けると、呼び出し元が
/// MainActor でも型は何も言わず、同期 syscall がメインへ紛れ込む余地が残る
/// (差分取得を detached にしたのにリポジトリルート解決だけ MainActor に残った
/// TASK-322 と同型)。辞書入力なら列挙は必ず呼び出し側の非同期経路で先に済み、
/// この関数は I/O を構造的に持てない。
enum SidebarRowBuilder {
    /// - Parameters:
    ///   - parentEntry: 親移動行(`..`)。無ければ nil。常に depth 0 の先頭に置く。
    ///   - rootChildren: ルート直下の行。並びは呼び出し元(DirectoryLister)が確定させる。
    ///   - expanded: 展開済みフォルダの正規化パスキー(`FileListEntry.pathKey`)の集合。
    ///     空ならドリルダウンと同じ出力になる。
    ///   - childrenByPathKey: フォルダの `pathKey` から、その直下の行への対応。
    ///     展開されているのに材料が無いフォルダは、子を持たない行として扱う。
    static func rows(
        parentEntry: FileListEntry?,
        rootChildren: [FileListEntry],
        expanded: Set<String>,
        childrenByPathKey: [String: [FileListEntry]]
    ) -> [FileListEntry] {
        var flattening = Flattening(expanded: expanded, childrenByPathKey: childrenByPathKey)
        if let parentEntry {
            flattening.rows.append(parentEntry.indented(to: 0))
        }
        flattening.append(rootChildren, depth: 0)
        return flattening.rows
    }

    /// 深さ優先の畳み込みの途中状態。展開集合・材料・訪問済みキー・出来上がりの行を
    /// 1 つにまとめている(再帰呼び出しに 6 個の引数を引き回さないため)。
    private struct Flattening {
        let expanded: Set<String>
        let childrenByPathKey: [String: [FileListEntry]]
        /// 展開済みとして既に降りたフォルダの pathKey。同じフォルダを 2 度展開しないための記録。
        ///
        /// FileListEntryIndex は「先に現れた行が勝つ」で重複を黙って飲み込むため、
        /// 同一 URL が 2 行に現れても落ちず、提示対象の解決だけが並び順依存になる。
        /// シンボリックリンク越しの循環(a/ → b/ → a/)による無限再帰もここで止まる。
        private var visited: Set<String> = []
        var rows: [FileListEntry] = []

        init(expanded: Set<String>, childrenByPathKey: [String: [FileListEntry]]) {
            self.expanded = expanded
            self.childrenByPathKey = childrenByPathKey
        }

        mutating func append(_ entries: [FileListEntry], depth: Int) {
            for entry in entries {
                rows.append(entry.indented(to: depth))
                guard entry.kind == .folder, expanded.contains(entry.pathKey) else { continue }
                guard visited.insert(entry.pathKey).inserted else { continue }
                append(childrenByPathKey[entry.pathKey] ?? [], depth: depth + 1)
            }
        }
    }
}
