import Foundation

// MARK: - Selection Memory

/// ディレクトリごとの「そこを離れる直前に選択していた項目」の記録と復元(TASK-309)。
/// 戻る/進む履歴(NavigationHistory)とは独立した関心事で、通常のクリックによる
/// フォルダー間の往復にだけ効く。記録はメモリ内のみで、ウィンドウの生存期間で自然に消える。
@MainActor
extension SidebarNavigator {
    /// 現在の選択を、そのディレクトリを離れる直前の選択として覚える。
    /// 選択が無いときは記憶を消し、次回の再訪で既定の挙動へ戻す。
    func rememberSelection(in directory: URL) {
        selectionMemory[directory.normalizedPathKey] = fileListModel.selection
    }

    /// `directory` で覚えている選択のうち、いま見えている一覧に残っているものを返す。
    /// 削除・リネーム・絞り込みで見えない場合は nil を返し、呼び出し元の既定挙動へ委ねる。
    func rememberedSelectionURL(in directory: URL) -> URL? {
        guard let remembered = selectionMemory[directory.normalizedPathKey] else { return nil }
        let key = remembered.normalizedPathKey
        return fileListModel.visibleEntries.first { $0.kind != .parentNavigation && $0.pathKey == key }?.url
    }
}
