import BefoldKit
import Foundation

/// ディレクトリごとの「そこを離れる直前に選択していた項目」を覚え、再訪時に返す。
/// 粒度は `SidebarExpansion` / `NavigationHistory` と同族で、ウィンドウごとに 1 つ・
/// メモリ内のみ(ウィンドウの生存期間で自然に消える / TASK-309)。
///
/// 覚えた URL をそのまま返さないのが要点。削除・リネーム・絞り込みで一覧から消えた
/// 項目を選択に書くと、存在しない行をハイライトしたまま残る。返すのは
/// 「いま見えている一覧に残っているもの」だけで、それ以外は nil を返して既定挙動へ委ねる。
@MainActor
final class SidebarSelectionMemory {
    /// 正規化キー → その時点の選択 URL。
    private var entries: [String: URL] = [:]
    /// 可視判定の材料。書き込みはせず、選択と可視行だけを読む。
    private let fileListModel: FileListModel

    init(fileListModel: FileListModel) {
        self.fileListModel = fileListModel
    }

    /// 現在の選択を、そのディレクトリを離れる直前の選択として覚える。
    /// 選択が無いときは記憶を消し、次回の再訪で既定の挙動へ戻す。
    func remember(in directory: URL) {
        entries[directory.normalizedPathKey] = fileListModel.selection
    }

    /// `directory` で覚えている選択のうち、いま見えている一覧に残っているものを返す。
    func rememberedURL(in directory: URL) -> URL? {
        guard let remembered = entries[directory.normalizedPathKey] else { return nil }
        let key = remembered.normalizedPathKey
        return fileListModel.visibleEntries.first { $0.pathKey == key }?.url
    }
}
