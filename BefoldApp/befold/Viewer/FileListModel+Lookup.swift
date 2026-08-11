import Foundation

/// 一覧を正規化パスキーから引き当てる述語。
///
/// サイドバーの移動・履歴適用・展開はいずれも「このキーの行が一覧にあるか」を
/// 問うだけで、問い方は移動元(SidebarNavigator 側の関心)によらない。一覧を持つ
/// この型に置くことで、引き当ての基準(`pathKey` による正規化比較)を一覧と同じ
/// 場所に閉じる(TASK-442.2)。
extension FileListModel {
    /// エントリ一覧からフォルダーの正規化キーが一致するものを返す。
    /// 同じキーの行が複数あるときは、索引と同じく先に現れた行を採る。
    func folderEntryURL(forKey key: String) -> URL? {
        guard let entry = entry(forPathKey: key), entry.kind == .folder else { return nil }
        return entry.url
    }

    /// エントリ一覧から URL の正規化キーが一致するものを探し、
    /// 見つからなければ元の URL をそのまま返す。
    func matchingEntryURL(for url: URL) -> URL {
        entry(forPathKey: url.normalizedPathKey)?.url ?? url
    }
}
