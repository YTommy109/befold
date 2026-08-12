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
///
/// **`byPathKey` の先勝ちは kind を見ない。** 「この kind の行を引きたい」という問いを
/// この辞書では表せない(先に確定した 1 行が別の kind だと、後ろに答えがあっても外れる)。
/// フォルダー行だけを引く問いは、そのための辞書(`folderByPathKey`)を別に持たせて
/// 答える(TASK-450 / TASK-443)。索引の外で線形走査を書き足さないこと。
struct FileListEntryIndex {
    private let byID: [FileListEntry.ID: FileListEntry]
    private let byPathKey: [String: FileListEntry]
    /// `kind == .folder` の行だけを集めた辞書。同じキーの非フォルダー行(実体と並ぶリンク、
    /// 祖先を指すリンクがあるときの `.parentNavigation` 行)が先にあっても外れないようにする。
    /// 先勝ちの規則は `byPathKey` と揃える。
    private let folderByPathKey: [String: FileListEntry]

    init(entries: [FileListEntry] = []) {
        var byID = [FileListEntry.ID: FileListEntry](minimumCapacity: entries.count)
        var byPathKey = [String: FileListEntry](minimumCapacity: entries.count)
        var folderByPathKey = [String: FileListEntry]()
        for entry in entries {
            if byID[entry.id] == nil { byID[entry.id] = entry }
            if byPathKey[entry.pathKey] == nil { byPathKey[entry.pathKey] = entry }
            if entry.kind == .folder, folderByPathKey[entry.pathKey] == nil {
                folderByPathKey[entry.pathKey] = entry
            }
        }
        self.byID = byID
        self.byPathKey = byPathKey
        self.folderByPathKey = folderByPathKey
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

    /// キーが一致する最初の**フォルダー行**の URL。
    ///
    /// サイドバーの移動・履歴適用・展開はいずれも「このキーのフォルダー行が一覧にあるか」を
    /// 問うだけで、問い方は移動元(SidebarNavigator 側の関心)によらない。一覧を索引化した
    /// この型に置くことで、引き当ての基準(`pathKey` による正規化比較)を一覧と同じ場所に
    /// 閉じる(TASK-442.2)。
    func folderEntryURL(forKey key: String) -> URL? {
        folderByPathKey[key]?.url
    }

    /// URL の正規化キーが一致する行を探し、見つからなければ元の URL をそのまま返す。
    func matchingEntryURL(for url: URL) -> URL {
        byPathKey[url.normalizedPathKey]?.url ?? url
    }
}
