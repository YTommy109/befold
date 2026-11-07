import Foundation

/// サイドバー開閉の保存値。ADR 0002 の「窓の状態」で、アプリ全体に 1 つだけ持つ。
///
/// ライブ値は窓ごと(`ViewerSplitViewController`)にあり、ここは起点の窓が無い新規ウィンドウと
/// 再起動後の初期値にしか使わない。書くのは利用者の開閉操作だけで、窓を開いただけでは
/// 書かない。窓を開くたびに解決結果を書くと、利用者の選択ではない値が保存値を上書きする。
@MainActor
final class SidebarStateStore {
    private static let lastToggledKey = "SidebarLastToggledCollapsed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 利用者がサイドバーを明示的に開閉したときに呼ぶ。
    func recordToggle(_ collapsed: Bool) {
        defaults.set(collapsed, forKey: Self.lastToggledKey)
    }

    /// 利用者が最後に操作した開閉状態。未操作なら既定(閉じた状態 = true)。
    var lastToggledCollapsed: Bool {
        guard defaults.object(forKey: Self.lastToggledKey) != nil else { return true }
        return defaults.bool(forKey: Self.lastToggledKey)
    }
}
