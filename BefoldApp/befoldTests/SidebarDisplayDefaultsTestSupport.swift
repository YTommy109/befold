@testable import befold

/// テスト専用: 既定値ストアの 1 値だけを変えて記録する。
///
/// 本番の書き戻しは `SidebarListingCoordinator.applyDisplayChange(_:)` が
/// 4 値まとめて `record(_:)` へ渡す形なので、プロパティごとの setter は用意していない。
/// テストが「保存済みの初期値」を用意するためだけの糖衣。
extension SidebarDisplayDefaults {
    func record(_ mutate: (inout SidebarDisplaySettings) -> Void) {
        var next = settings
        mutate(&next)
        record(next)
    }
}
