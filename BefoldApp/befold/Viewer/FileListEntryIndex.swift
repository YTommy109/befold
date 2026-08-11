import Foundation

/// サイドバー一覧を選択(URL)から引くための索引。
///
/// 提示対象の解決は menu validation(1 回のメニュー表示で 7 セレクタぶん)・ツールバー同期・
/// View の body 評価と何度も走る。そのたびに `entries.first(where:)` の線形走査を回すと
/// 数万件のディレクトリでメインスレッドが詰まるため(TASK-273)、走査は一覧の代入時に
/// 一度だけ行い、以降の引き当てを O(1) にする。
///
/// `pathKey` 側は「先に現れた行が勝つ」。線形走査で `entries.first { $0.pathKey == key }` を
/// 使っていたときと同じ行を返すため(同じ実体を指す行が複数あるとき、たとえば同一
/// フォルダー内のシンボリックリンクと実体が並ぶとき、選ばれる行を変えない)。
struct FileListEntryIndex {
    private let byID: [FileListEntry.ID: FileListEntry]
    private let byPathKey: [String: FileListEntry]

    init(entries: [FileListEntry] = []) {
        var byID = [FileListEntry.ID: FileListEntry](minimumCapacity: entries.count)
        var byPathKey = [String: FileListEntry](minimumCapacity: entries.count)
        for entry in entries {
            if byID[entry.id] == nil { byID[entry.id] = entry }
            if byPathKey[entry.pathKey] == nil { byPathKey[entry.pathKey] = entry }
        }
        self.byID = byID
        self.byPathKey = byPathKey
    }

    /// 選択に対応する行。まず ID(URL)で照合し、外れたときだけ正規化パスキーで照合し直す。
    ///
    /// シンボリックリンク経由のパス(`/tmp/...` と `/private/tmp/...` など)で開かれると、
    /// 一覧の URL と選択の URL は同じファイルを指しながら文字列としては一致しない。
    /// 一方 SidebarNavigator の選択維持判定は正規化キーで比較して「選択は有効」と結論するため、
    /// 両者が食い違うと、**選択は保持されたまま提示対象だけがフォルダーへ落ちる**
    /// (文書を開いたのに一覧が出る)。照合の基準をここで揃える(ADR 0002)。
    ///
    /// - Parameter selectionPathKey: 選択の `normalizedPathKey`。解決のたびに syscall を
    ///   起こさないよう、呼び出し側が選択の書き込み時に採った値を渡す。
    func entry(for selection: FileListEntry.ID, selectionPathKey: String) -> FileListEntry? {
        byID[selection] ?? byPathKey[selectionPathKey]
    }

    /// 正規化パスキーに対応する行。同じキーの行が複数あるときは先に現れた行を返す。
    func entry(forPathKey key: String) -> FileListEntry? {
        byPathKey[key]
    }
}
