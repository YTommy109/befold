import Foundation

/// ツリー表示のフォルダ行に出す開閉三角の状態。
///
/// 行に焼き込む値であり、View がストアを読んで判定するのではない。
/// `SidebarExpansion` は意図的に `@Observable` ではなく(描画の真実の源を
/// `FileListModel.entries` の 1 本に保つため)、View から読んでも再描画が飛ばない。
enum SidebarDisclosureState: Sendable, Hashable {
    /// 畳んでいる。
    case collapsed
    /// 展開したが、子リストがまだ届いていない。
    case loadingChildren
    /// 展開済みで、見えている子がある。
    case expanded
    /// 展開済みだが、見えている子が 0。
    ///
    /// `isFiltered` は「絞り込みで消えたのか、本当に空のフォルダなのか」の区別。
    /// **判定は子リストの件数という事実**(`.loaded` の件数と絞り込み後の件数の比較)で
    /// 行い、配列が空かどうかだけで決めない。`.loading` を「空」と取り違えると
    /// 読み込み中が「空のフォルダ」として確定表示される。
    case expandedEmpty(isFiltered: Bool)
}

/// 開閉三角の状態を決める純粋関数。
///
/// GUI 層は自動テスト対象外なので、3 つの状態(未到着 / 空フォルダ / 絞り込みで 0)を
/// 区別できていることはこの関数のユニットテストが唯一の測り方になる
/// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
enum SidebarDisclosure {
    /// - Parameters:
    ///   - isExpanded: 展開する意図があるか(`SidebarExpansion.expandedKeys` に含まれるか)。
    ///   - loadedChildCount: 届いている子の件数。**まだ届いていないなら nil**。
    ///     0 と nil を分けるのが要点で、混ぜると読み込み中が空フォルダとして表示される。
    ///   - visibleChildCount: 絞り込み後に実際に行として並ぶ子の件数。
    static func state(
        isExpanded: Bool, loadedChildCount: Int?, visibleChildCount: Int
    ) -> SidebarDisclosureState {
        guard isExpanded else { return .collapsed }
        guard let loadedChildCount else { return .loadingChildren }
        guard visibleChildCount == 0 else { return .expanded }
        // 届いている子はあるのに 1 行も出ていない = 絞り込みで消えた。
        return .expandedEmpty(isFiltered: loadedChildCount > 0)
    }
}
