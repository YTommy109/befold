@testable import befold
import CoreGraphics
import Testing

/// サイドバー行のインデント量。GUI 層は自動テスト対象外なので、
/// 「ドリルダウン表示では見た目が変わらない」(TASK-361.1 の AC #5)は
/// この純粋関数を測ることでしか担保できない。
@Suite
struct SidebarRowIndentTests {
    @Test("depth 0 はインデント 0pt(ドリルダウン表示の見た目が変わらない)")
    func zeroDepthHasNoInset() {
        #expect(SidebarRowIndent.leadingInset(forDepth: 0) == 0)
    }

    @Test("depth が 1 増えるごとに 1 段ぶん深くなる")
    func insetGrowsByStepPerDepth() {
        #expect(SidebarRowIndent.leadingInset(forDepth: 1) == SidebarRowIndent.step)
        #expect(SidebarRowIndent.leadingInset(forDepth: 3) == SidebarRowIndent.step * 3)
    }

    /// depth は `indented(to:)` 経由でしか書けないが、負値を渡せてしまう口は残る。
    /// 負のインセットは行を左へはみ出させるため、ここで 0 に丸める。
    @Test("負の depth は 0pt に丸める")
    func negativeDepthClampsToZero() {
        #expect(SidebarRowIndent.leadingInset(forDepth: -1) == 0)
    }
}
