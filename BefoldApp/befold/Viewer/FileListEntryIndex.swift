import Foundation

/// サイドバー一覧をパスキーから引くための索引。
///
/// 行の引き当ては View の body 評価・キー操作・選択の確定と何度も走る。そのたびに
/// `entries.first(where:)` の線形走査を回すと数万件のディレクトリでメインスレッドが
/// 詰まるため(TASK-273)、走査は一覧の代入時に一度だけ行い、以降の引き当てを O(1) にする。
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
    private let byPathKey: [String: FileListEntry]
    /// `kind == .folder` の行だけを集めた辞書。同じキーの非フォルダー行(実体と並ぶ
    /// シンボリックリンク)が先にあっても外れないようにする。
    /// 先勝ちの規則は `byPathKey` と揃える。
    private let folderByPathKey: [String: FileListEntry]

    init(entries: [FileListEntry] = []) {
        var byPathKey = [String: FileListEntry](minimumCapacity: entries.count)
        var folderByPathKey = [String: FileListEntry]()
        for entry in entries {
            if byPathKey[entry.pathKey] == nil { byPathKey[entry.pathKey] = entry }
            if entry.kind == .folder, folderByPathKey[entry.pathKey] == nil {
                folderByPathKey[entry.pathKey] = entry
            }
        }
        self.byPathKey = byPathKey
        self.folderByPathKey = folderByPathKey
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
