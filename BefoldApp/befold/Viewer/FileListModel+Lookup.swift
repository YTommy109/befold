import Foundation

/// 一覧を正規化パスキーから引き当てる述語。
///
/// サイドバーの移動・履歴適用・展開はいずれも「このキーの行が一覧にあるか」を
/// 問うだけで、問い方は移動元(SidebarNavigator 側の関心)によらない。一覧を持つ
/// この型に置くことで、引き当ての基準(`pathKey` による正規化比較)を一覧と同じ
/// 場所に閉じる(TASK-442.2)。
extension FileListModel {
    /// キーが一致する最初の**フォルダー行**の URL。索引(`entry(forPathKey:)`)は kind を
    /// 見ずに先勝ちで 1 行へ確定するため使えない——同じキーの非フォルダー行(実体と並ぶ
    /// リンク、祖先を指すリンクがあるときの `.parentNavigation` 行)が先だと nil になる(TASK-450)。
    func folderEntryURL(forKey key: String) -> URL? {
        entries.first { $0.kind == .folder && $0.pathKey == key }?.url
    }

    /// エントリ一覧から URL の正規化キーが一致するものを探し、
    /// 見つからなければ元の URL をそのまま返す。
    func matchingEntryURL(for url: URL) -> URL {
        entry(forPathKey: url.normalizedPathKey)?.url ?? url
    }
}
