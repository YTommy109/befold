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

    /// `List`(NSTableView 裏打ち)が行の外側に持つ左右のインセットの実測値。
    ///
    /// **机上では出せない値**なので、実機で幅を詰めて測った結果をここに焼く。
    /// 測り方と根拠は TASK-585 の Implementation Notes に残す。
    static let measuredListInset: CGFloat = 0

    /// 与えられた `List` のインセットに対するスライドモードの幅。
    ///
    /// 左右のパディング + 開閉三角 + 間隔 + アイコン。名前の分は足さない
    /// (名前が隠れることがこのモードの狙いのため)。
    static func width(listInset: CGFloat) -> CGFloat {
        SidebarRowIndent.rowHorizontalPadding * 2
            + SidebarRowIndent.disclosureWidth
            + rowContentSpacing
            + iconWidth
            + listInset
    }

    /// 実際に使う幅。
    static var width: CGFloat {
        width(listInset: measuredListInset)
    }
}
