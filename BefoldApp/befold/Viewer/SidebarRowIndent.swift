import CoreGraphics

/// サイドバー行の深さ→左インデント量。
///
/// 純粋関数として切り出しているのは、GUI 層が自動テスト対象外だから。
/// 「ドリルダウン表示では見た目が変わらない」(= depth 0 でインデント 0)は、
/// この関数のユニットテストが唯一の測り方になる
/// (`ModeSegments.modes(isSourceDiffEnabled:)` と同じ形)。
enum SidebarRowIndent {
    /// 1 段ぶんのインデント幅。Finder のリスト表示に合わせる。
    static let step: CGFloat = 16

    static func leadingInset(forDepth depth: Int) -> CGFloat {
        CGFloat(max(0, depth)) * step
    }
}
