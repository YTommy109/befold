@testable import befold
import CoreGraphics
import Testing

/// スライドモードのサイドバー幅の幾何。GUI 層は自動テスト対象外なので、
/// 「アイコンは見えてファイル名は隠れる」を測れるのはこの純粋関数だけ。
@Suite
struct SidebarSlideMetricsTests {
    @Test("幅は行の左端からアイコン右端までの合計に List のインセットを足したもの")
    func widthSumsRowGeometryAndListInset() {
        let expected = SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + SidebarSlideMetrics.rowContentSpacing
            + SidebarSlideMetrics.iconWidth
            + 7

        #expect(SidebarSlideMetrics.width(listInset: 7) == expected)
    }

    @Test("既定の幅は実測した List のインセットを使う")
    func defaultWidthUsesMeasuredInset() {
        #expect(
            SidebarSlideMetrics.width
                == SidebarSlideMetrics.width(listInset: SidebarSlideMetrics.measuredListInset)
        )
    }

    @Test("ファイル名が始まる位置より広く、通常の下限より狭い")
    func widthSitsBetweenIconColumnAndMinimumSidebarWidth() {
        let iconRightEdge = SidebarRowIndent.rowHorizontalPadding
            + SidebarRowIndent.disclosureWidth
            + SidebarSlideMetrics.rowContentSpacing
            + SidebarSlideMetrics.iconWidth
        #expect(SidebarSlideMetrics.width > iconRightEdge)
        #expect(SidebarSlideMetrics.width < 200)
    }
}
