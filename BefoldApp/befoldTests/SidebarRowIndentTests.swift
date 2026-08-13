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

    /// 開閉三角のクリック領域(TASK-472)。表示側の `.frame(width:)` と同じ定数から
    /// 組み立てているので、片方だけ変えれば必ずここが落ちる。
    @Test("三角の領域は行のパディング直後から三角の幅ぶん")
    func disclosureRegionStartsAfterRowPadding() {
        let padding = SidebarRowIndent.rowHorizontalPadding
        #expect(!SidebarRowIndent.isWithinDisclosure(offsetX: padding - 1, depth: 0))
        #expect(SidebarRowIndent.isWithinDisclosure(offsetX: padding, depth: 0))
        #expect(
            SidebarRowIndent.isWithinDisclosure(
                offsetX: padding + SidebarRowIndent.disclosureWidth - 1, depth: 0
            )
        )
        #expect(
            !SidebarRowIndent.isWithinDisclosure(
                offsetX: padding + SidebarRowIndent.disclosureWidth, depth: 0
            )
        )
    }

    /// 深い行では三角も同じだけ右へ寄る。インデント部分(三角より左)は含めない
    /// ——含めると誤って開閉する領域が深い行ほど広がる。
    @Test("深い行では三角の領域がインデントぶん右へずれる")
    func disclosureRegionShiftsWithDepth() {
        let padding = SidebarRowIndent.rowHorizontalPadding
        for depth in 1 ... 2 {
            let start = padding + SidebarRowIndent.leadingInset(forDepth: depth)
            // 同じ座標が depth 0 では三角、この行ではインデントの上。
            #expect(!SidebarRowIndent.isWithinDisclosure(offsetX: padding, depth: depth))
            #expect(SidebarRowIndent.isWithinDisclosure(offsetX: start, depth: depth))
            #expect(!SidebarRowIndent.isWithinDisclosure(offsetX: start - 1, depth: depth))
        }
    }
}
