import CoreGraphics

/// サイドバー行の幾何(左インデント量・開閉三角の位置)。
///
/// 純粋関数として切り出しているのは、GUI 層が自動テスト対象外だから。
/// 「ドリルダウン表示では見た目が変わらない」(= depth 0 でインデント 0)は、
/// この関数のユニットテストが唯一の測り方になる
/// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
///
/// **三角の幅・行の水平パディングもここに置く。** 表示側(`FileListEntryRow`)と
/// 当たり判定側(`FileListView.disclosureAction(for:atX:)`)が別々に数値を持つと、
/// 片方だけ変えたときにクリック位置と見た目がずれる(TASK-472 の AC #3)。
enum SidebarRowIndent {
    /// 1 段ぶんのインデント幅。Finder のリスト表示に合わせる。
    static let step: CGFloat = 16

    /// 開閉三角の占める幅。`FileListEntryRow` の `.frame(width:)` と共有する。
    static let disclosureWidth: CGFloat = 12

    /// 行の中身に付ける左右のパディング。行の先頭からの座標を測るとき、
    /// 三角の開始位置はこのぶんだけ右へずれる。
    static let rowHorizontalPadding: CGFloat = 8

    static func leadingInset(forDepth depth: Int) -> CGFloat {
        CGFloat(max(0, depth)) * step
    }

    /// 行の左端(パディングを含む)からの水平座標が、開閉三角の上かどうか。
    ///
    /// インデント部分(三角より左)は含めない。Finder も三角より左をクリックしても
    /// 開閉しないため、含めると誤って開閉する領域が深い行ほど広がる。
    /// - Note: 三角の**有無**は座標では決まらない。呼び出し側が `entry.disclosure` を
    ///   先に見ること(`FileListView.disclosureAction(for:atX:)`)。
    static func isWithinDisclosure(offsetX: CGFloat, depth: Int) -> Bool {
        let start = rowHorizontalPadding + leadingInset(forDepth: depth)
        return offsetX >= start && offsetX < start + disclosureWidth
    }
}
