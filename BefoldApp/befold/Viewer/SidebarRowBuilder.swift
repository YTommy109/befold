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
///
/// ## 同じ pathKey を持つ行が複数あるとき
///
/// `pathKey` は `resolvingSymlinksInPath()` で解決した実体パスなので、同一フォルダー内に
/// シンボリックリンクと実体が並ぶと **2 行が同じキーを持つ**(TASK-450 の調査)。開閉状態
/// (`SidebarExpansion.expandedKeys` / `children`)はキー単位でしか持てず、リンク行と実体行を
/// 別々に開閉することはできない。
///
/// **区別しない方を決めた振る舞いとする**(TASK-454)。行ごとの開閉状態へ粒度を上げると、
/// 同じフォルダーの子リストを行の数だけ持つことになり、「展開 1 回につき列挙 1 回」という
/// `SidebarExpansion.beginExpanding` のコスト上限も崩れる。代わりに
/// **先に現れた 1 行だけが開閉状態の持ち主**になり、後続の重複行は三角を出さない
/// (`disclosure` が nil)。子行が並ぶのも持ち主の行の下だけなので、
/// 「三角は開いているのに子が出ない行」は生じない。固定しているのは `SidebarRowBuilderTests`。
enum SidebarRowBuilder {
    /// 行の組み立てへ渡す材料一式。`SidebarExpansion.material` が組み、
    /// `DirectoryListing.rows(material:showsDisclosure:)` が受け取る。
    ///
    /// **`SidebarExpansion` のネスト型ではなくここに置く。** あちらは `@MainActor` な
    /// クラスで、ネストするとこの材料まで MainActor 隔離され、行の組み立て自体が
    /// MainActor を要求するようになる(行の畳み込みは I/O も UI も持たない純粋計算で、
    /// 非 MainActor のテストから直接呼べる必要がある)。
    struct Material: Sendable, Equatable {
        /// 子が届いていて、実際に行を並べられるフォルダ。
        var expanded: Set<String> = []
        var childrenByPathKey: [String: [FileListEntry]] = [:]
        /// 展開する意図はあるが、子がまだ届いていないフォルダ。
        var loading: Set<String> = []
        /// 展開しようとしたが列挙に失敗したフォルダ。行は増やさない(並べる子が無い)が、
        /// 「空のフォルダ」とも「読み込み中」とも違う見た目にするために要る。
        var failed: Set<String> = []
    }

    /// - Parameters:
    ///   - rootChildren: ルート直下の行。並びは呼び出し元(DirectoryLister)が確定させる。
    ///   - expanded: 展開済みフォルダの正規化パスキー(`FileListEntry.pathKey`)の集合。
    ///     空ならドリルダウンと同じ出力になる。
    ///   - childrenByPathKey: フォルダの `pathKey` から、その直下の行への対応。
    ///     展開されているのに材料が無いフォルダは、子を持たない行として扱う。
    ///   - loading: 展開する意図はあるが、子リストがまだ届いていないフォルダの pathKey。
    ///     `expanded` とは互いに素。開閉三角を「読み込み中」にするためだけに使い、
    ///     行は増やさない(届いていない子は並べようがない)。
    ///   - failed: 展開しようとしたが列挙に失敗したフォルダの pathKey。`expanded` /
    ///     `loading` とは互いに素。`loading` と同じく行は増やさず、開閉三角の見た目
    ///     だけを決める。**ここへ渡さないと `.collapsed` に落ち**、失敗が「畳んでいる」
    ///     ように見えるうえ、→ キーが展開を出しても再展開が弾かれ無反応になる。
    ///   - showsDisclosure: 開閉三角を出すか。ドリルダウン表示では false にして、
    ///     フォルダ行の見た目を従来のまま(`disclosure` が nil)にする。
    static func rows(
        rootChildren: [FileListEntry],
        expanded: Set<String>,
        childrenByPathKey: [String: [FileListEntry]],
        loading: Set<String> = [],
        failed: Set<String> = [],
        showsDisclosure: Bool = false
    ) -> [FileListEntry] {
        var flattening = Flattening(
            expanded: expanded, childrenByPathKey: childrenByPathKey,
            loading: loading, failed: failed, showsDisclosure: showsDisclosure
        )
        flattening.append(rootChildren, depth: 0)
        return flattening.rows
    }

    /// 深さ優先の畳み込みの途中状態。展開集合・材料・訪問済みキー・出来上がりの行を
    /// 1 つにまとめている(再帰呼び出しに 6 個の引数を引き回さないため)。
    private struct Flattening {
        let expanded: Set<String>
        let childrenByPathKey: [String: [FileListEntry]]
        /// 既に開閉状態の持ち主として現れたフォルダの pathKey。同じフォルダを
        /// 2 度展開しないための記録。
        ///
        /// FileListEntryIndex は「先に現れた行が勝つ」で重複を黙って飲み込むため、
        /// 同一 URL が 2 行に現れても落ちず、提示対象の解決だけが並び順依存になる。
        /// シンボリックリンク越しの循環(a/ → b/ → a/)による無限再帰もここで止まる。
        ///
        /// **フォルダ行なら展開されていなくても記録する**(TASK-454)。展開済みの行だけを
        /// 記録していた頃は、同じ pathKey を持つ 2 行(同一フォルダー内にシンボリックリンクと
        /// 実体が並ぶ場合)が揃って `expanded` に一致し、両方が開いた三角になる一方で
        /// 子行が並ぶのは先の 1 行だけだった。つまり後の行は
        /// 「三角は開いているのに子が出ない」状態になっていた。
        private var visited: Set<String> = []
        var rows: [FileListEntry] = []

        let loading: Set<String>
        let failed: Set<String>
        let showsDisclosure: Bool

        init(
            expanded: Set<String>, childrenByPathKey: [String: [FileListEntry]],
            loading: Set<String>, failed: Set<String>, showsDisclosure: Bool
        ) {
            self.expanded = expanded
            self.childrenByPathKey = childrenByPathKey
            self.loading = loading
            self.failed = failed
            self.showsDisclosure = showsDisclosure
        }

        mutating func append(_ entries: [FileListEntry], depth: Int) {
            for entry in entries {
                // 開閉状態の持ち主かどうかを**三角を決める前に**確定させる。順序を逆にすると
                // 持ち主でない重複行にも開いた三角が出る(TASK-454)。
                let ownsExpansion = entry.kind == .folder && visited.insert(entry.pathKey).inserted
                rows.append(
                    entry.indented(to: depth)
                        .disclosing(disclosure(for: entry, ownsExpansion: ownsExpansion))
                )
                guard ownsExpansion, expanded.contains(entry.pathKey) else { continue }
                append(childrenByPathKey[entry.pathKey] ?? [], depth: depth + 1)
            }
        }

        /// この行に出す開閉三角。ここで決まるのは絞り込み**前**の状態で、
        /// 「絞り込みで見えている子が 0 になった」の確定は SidebarDisclosureResolver が行う。
        ///
        /// - Parameter ownsExpansion: この行が pathKey の開閉状態の持ち主か。
        ///   持ち主でない重複行では **nil**(三角を出さない)にする。開閉状態は pathKey 単位で
        ///   しか持てず、この行を単独で開閉する手段が無いため、畳んだ三角
        ///   (`.collapsed`)を出すと押しても何も起きないことになる。三角が無ければ
        ///   「この行では開閉できない」ことがそのまま見た目になり、どの行が展開の
        ///   持ち主かも区別できる(TASK-454)。
        private func disclosure(
            for entry: FileListEntry, ownsExpansion: Bool
        ) -> SidebarDisclosureState? {
            guard showsDisclosure, entry.kind == .folder, ownsExpansion else { return nil }
            let key = entry.pathKey
            return SidebarDisclosure.state(
                isExpanded: expanded.contains(key) || loading.contains(key) || failed.contains(key),
                didFail: failed.contains(key),
                loadedChildCount: childrenByPathKey[key]?.count,
                visibleChildCount: childrenByPathKey[key]?.count ?? 0
            )
        }
    }
}
