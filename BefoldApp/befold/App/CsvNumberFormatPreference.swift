import BefoldKit
import Foundation

/// CSV/TSV テーブル表示の数値の見せ方(アプリ全体の設定)。
///
/// 右寄せは設定にしない(常時)。桁区切りの有無と負の数の表記だけを持つ。
/// `CodeFontPreference` と同じく UserDefaults を直に読み書きし、`didSet` で
/// 書き戻す。`@Observable` にはしないので、View 側は `@State` を持ち
/// `onChange` で書き戻す write-through 方式に倣うこと。
///
/// アプリ全体で 1 つであることは `AppStores` が唯一のインスタンスを持つことで
/// 担保する。注入先の初期化引数には**既定値を付けない**(既定値を付けると、
/// 渡し忘れがコンパイルエラーにならず静かに別インスタンスになる)。
@MainActor final class CsvNumberFormatPreference {
    private static let groupingKey = "CsvNumberGrouping"
    private static let negativeStyleKey = "CsvNegativeStyle"

    private let defaults: UserDefaults

    /// 数値列に桁区切りを入れるか。既定はオン。
    var grouping: Bool {
        didSet { defaults.set(grouping, forKey: Self.groupingKey) }
    }

    /// 負の数の表記。既定は通常表記。
    var negativeStyle: CsvNegativeStyle {
        didSet { defaults.set(negativeStyle.rawValue, forKey: Self.negativeStyleKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 未設定と「明示的にオフ」を区別する必要があるため bool(forKey:) を直に
        // 使わない(未設定でも false が返るため、既定のオンにできない)。
        let storedGrouping = defaults.object(forKey: Self.groupingKey) as? Bool
        grouping = storedGrouping ?? true
        negativeStyle = CsvNegativeStyle.from(
            rawValue: defaults.string(forKey: Self.negativeStyleKey)
        )
    }
}
