import BefoldKit
import Foundation

/// ソース表示に重ねる git 差分の**レイアウト**（1 列 / 左右分割）を UserDefaults に永続化する。
///
/// 粒度はアプリ全体（`SidebarDisplayPreference` と同じ「注入して全ウィンドウで共有する」形）。
/// レイアウトは「どちらの並びが読みやすいか」という好みの設定であってファイル固有の性質ではない。
/// 差分を出すかどうか自体は表示モード（`ViewerDisplayMode.diff`）としてファイル単位で持つため、
/// ここには載せない。
///
/// `@Observable` にしているのは、レイアウト変更が SwiftUI の再評価を引き起こす必要があるため。
/// 表示モードの変更は `store` 経由で反映されるが、レイアウトはこの値しか変わらず、
/// 観測していないと切り替えても描画が変わらない(実機で再現した)。
///
/// アプリ全体で 1 個という粒度を構造で守るため、イニシャライザに既定値を持たせない。
/// 既定値があると渡し忘れがコンパイルエラーにならず、静かに窓ごとの別インスタンスになる
/// （実際に 2 窓でトグルが同期しない不具合になった = TASK-319）。
@MainActor
@Observable
final class DiffDisplayPreference {
    private let defaults: UserDefaults
    private static let layoutKey = "SourceDiffLayout"

    /// 差分のレイアウト（1 列 / 左右分割）。
    var layout: ViewerBridge.DiffLayout {
        didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.layoutKey)
        layout = stored.flatMap(ViewerBridge.DiffLayout.init(rawValue:)) ?? .inline
    }
}
