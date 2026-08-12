import Foundation

/// 行番号付きコード表示を有効にするかどうかの設定。値は UserDefaults に永続化する。
///
/// 粒度は**窓ごと**（`ViewerStore` が init で 1 つ生成して `let` で保持する）。保存先の
/// キーはアプリ全体で 1 つだが、生きている窓どうしを同期はしない — 保存値は「次に窓を
/// 開くときの既定値」であり、他窓の操作が後から効かないようにするため（ADR 0002
/// 「文書の状態の規則」と同じ考え方）。全窓共有の設定（`DiffDisplayPreference` など）とは
/// 粒度が違うので、あちらのように外から注入する形にはしない。
///
/// `@Observable` にしているのは、行番号のトグルが SwiftUI の再評価を引き起こす必要が
/// あるため（`ViewerContentView` が `store.showLineNumbers` を読む）。
@MainActor
@Observable
final class ShowLineNumbersSetting {
    private static let key = "ShowLineNumbers"

    private let defaults: UserDefaults

    /// applyOverride 実行中だけ true になり、didSet の永続化書き込みを抑止する。
    private var suppressPersistence = false

    var isEnabled: Bool {
        didSet {
            guard !suppressPersistence else { return }
            defaults.set(isEnabled, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
    }

    /// CLI の `--line-numbers`/`--no-line-numbers` から渡される、この起動限りの上書きを適用する。
    /// didSet(UserDefaults への永続化)を経由しないため、保存済みのグローバル設定は書き換えない。
    /// store が呼び出し元から明示注入された場合でも、この起動限りの上書きが確実に反映される
    /// よう、store 生成後に呼び出す想定。
    func applyOverride(_ value: Bool) {
        suppressPersistence = true
        isEnabled = value
        suppressPersistence = false
    }
}
