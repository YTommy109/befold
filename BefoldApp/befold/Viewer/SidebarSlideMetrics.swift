import CoreGraphics

/// スライドモード中のサイドバー幅の幾何(TASK-585)。
///
/// `SidebarRowIndent` と同じ理由でここに純粋な値として置く。GUI 層は自動テスト対象外
/// なので、「左端のアイコンは見えてファイル名は隠れる」という条件を測れるのは
/// この関数のユニットテストだけになる。
enum SidebarSlideMetrics {
    /// 行の `HStack` が三角とアイコンの間に入れる間隔(`FileListEntryRow` の spacing)。
    static let rowContentSpacing: CGFloat = 2

    /// 行アイコンの一辺(`FileListEntryRow` の nameLabel が与える frame)。
    static let iconWidth: CGFloat = 16

    /// `NSSplitViewItem` の thickness に渡す幅。
    ///
    /// **thickness が効くのは内容部分(List)であって、サイドバーの見た目の幅ではない。**
    /// 実測(2026-09-04): 通常時は `_NSSplitViewItemViewWrapper` が 303pt で、その中の
    /// `NSContainerConcentricGlassEffectView` が `x=8.0 w=295.0` だった。thickness に 54 を
    /// 渡したときの wrapper は 62pt で、いずれも「wrapper = 内容 + 8」の関係にある。
    /// したがってここでは AppKit が足す 8pt を含めない。見た目の幅は 8pt 広くなる。
    ///
    /// 内訳は行の左パディング + 開閉三角 + 間隔 + アイコン + 行の右パディング。
    /// 名前の分は足さない(名前が隠れることがこのモードの狙いのため)。
    static var thickness: CGFloat {
        SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + rowContentSpacing
            + iconWidth
    }

    /// 行アイコンの右端が行の左端から何 pt の位置にあるか。
    /// `thickness` がこれを下回るとアイコンが切れる。
    static var iconTrailingEdge: CGFloat {
        SidebarRowIndent.rowHorizontalPadding
            + SidebarRowIndent.disclosureWidth
            + rowContentSpacing
            + iconWidth
    }
}
