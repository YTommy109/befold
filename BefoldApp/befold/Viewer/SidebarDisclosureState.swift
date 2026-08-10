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
    /// 展開しようとしたが、ディレクトリの列挙に失敗した(権限が無い・消えた)。
    ///
    /// **「空のフォルダ」とも「読み込み中」とも別にする。** 空として確定表示すると
    /// 読めなかっただけのフォルダを「中身が無い」と言い切ることになり、読み込み中の
    /// ままにすると永久にスピナーが回る(TASK-404)。
    case expandedFailed
}

/// 開閉三角の状態を決める純粋関数。
///
/// GUI 層は自動テスト対象外なので、3 つの状態(未到着 / 空フォルダ / 絞り込みで 0)を
/// 区別できていることはこの関数のユニットテストが唯一の測り方になる
/// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
enum SidebarDisclosure {
    /// - Parameters:
    ///   - isExpanded: 展開する意図があるか(`SidebarExpansion.expandedKeys` に含まれるか)。
    ///   - didFail: そのフォルダの列挙に失敗したか。**既定値を持たせない**のは、
    ///     渡し忘れがコンパイルエラーにならず静かに「失敗しない」側へ倒れるため。
    ///   - loadedChildCount: 届いている子の件数。**まだ届いていないなら nil**。
    ///     0 と nil を分けるのが要点で、混ぜると読み込み中が空フォルダとして表示される。
    ///   - visibleChildCount: 絞り込み後に実際に行として並ぶ子の件数。
    static func state(
        isExpanded: Bool, didFail: Bool, loadedChildCount: Int?, visibleChildCount: Int
    ) -> SidebarDisclosureState {
        guard isExpanded else { return .collapsed }
        // 失敗は未到着・空より**先に**確定させる。失敗したフォルダには届く子リストが
        // 無く loadedChildCount は永久に nil のままなので、順序を逆にすると
        // 読み込み中として回り続ける。
        guard !didFail else { return .expandedFailed }
        guard let loadedChildCount else { return .loadingChildren }
        guard visibleChildCount == 0 else { return .expanded }
        // 届いている子はあるのに 1 行も出ていない = 絞り込みで消えた。
        return .expandedEmpty(isFiltered: loadedChildCount > 0)
    }
}
