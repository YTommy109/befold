@testable import befold
import CoreGraphics
import Testing

/// スライドモードのサイドバー幅の幾何。GUI 層は自動テスト対象外なので、
/// 「アイコンは見えてファイル名は隠れる」を測れるのはこの値だけ。
@Suite
struct SidebarSlideMetricsTests {
    @Test("thickness は行の左右パディング・三角・間隔・アイコンの合計")
    func thicknessSumsRowGeometry() {
        let expected = SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + SidebarSlideMetrics.rowContentSpacing
            + SidebarSlideMetrics.iconWidth

        #expect(SidebarSlideMetrics.thickness == expected)
    }

    @Test("アイコンは切れず、名前の分の余地は残らない")
    func thicknessShowsIconAndHidesName() {
        // アイコンの右端を下回るとアイコンが切れる。
        #expect(SidebarSlideMetrics.thickness >= SidebarSlideMetrics.iconTrailingEdge)
        // アイコンの右に残るのは行の右パディングだけ。名前が入る余地を作らない。
        #expect(
            SidebarSlideMetrics.thickness - SidebarSlideMetrics.iconTrailingEdge
                == SidebarRowIndent.rowHorizontalPadding
        )
    }

    @Test("通常モードの下限(200)より明確に狭い")
    func thicknessIsNarrowerThanMinimumSidebarWidth() {
        // ViewerSplitViewController.minimumSidebarWidth はジェネリック型の静的プロパティで
        // テストから具体化しづらいため、値そのものを書く。両方を変えるときは揃えること。
        #expect(SidebarSlideMetrics.thickness < 200)
    }
}
