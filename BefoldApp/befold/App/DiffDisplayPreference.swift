import BefoldKit
import Foundation

/// ソース表示に重ねる git 差分の表示設定を UserDefaults に永続化する。
///
/// 粒度はアプリ全体（`SidebarDisplayPreference` と同じ「注入して全ウィンドウで共有する」形）。
/// 差分を見るかどうかは「いまの作業の見方」であってファイル固有の性質ではないため、
/// per-file の `SourceModeStore` には載せない。ウィンドウごとに違う答えになると、
/// 同じファイルを 2 枚開いたときにどちらが正しいのか決められなくなる。
/// `@Observable` にしているのは、レイアウト変更が SwiftUI の再評価を引き起こす必要があるため。
/// ON/OFF は `store.diffText` を動かすので観測なしでも反映されるが、レイアウトは
/// この値しか変わらず、観測していないと切り替えても描画が変わらない(実機で再現した)。
@MainActor
@Observable
final class DiffDisplayPreference {
    private let defaults: UserDefaults
    private static let isEnabledKey = "SourceDiffEnabled"
    private static let layoutKey = "SourceDiffLayout"

    /// ソース表示中に git 差分を出すか。
    /// 機能が無効なビルドでは切り替える手段が露出しないため、保存値が ON でも OFF として読む
    /// （保存値そのものは書き換えないので、dev ビルドへ戻れば ON のまま復帰する）。
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.isEnabledKey) }
    }

    /// 差分のレイアウト（1 列 / 左右分割）。
    var layout: ViewerBridge.DiffLayout {
        didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    /// - Parameter isAvailable: 既定はフィーチャーゲートの判定。
    ///   テストから両方の状態を作れるようにするためだけの注入点で、本番では省略する。
    init(
        defaults: UserDefaults = .standard,
        isAvailable: Bool = FeatureGate.isSourceDiffEnabled
    ) {
        self.defaults = defaults
        isEnabled = isAvailable && defaults.bool(forKey: Self.isEnabledKey)
        let stored = defaults.string(forKey: Self.layoutKey)
        layout = stored.flatMap(ViewerBridge.DiffLayout.init(rawValue:)) ?? .inline
    }
}
