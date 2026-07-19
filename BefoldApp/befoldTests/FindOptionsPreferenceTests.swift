@testable import befold
import BefoldKit
import Foundation
import Testing

@Suite
@MainActor
struct FindOptionsPreferenceTests {
    @Test("デフォルトはすべて false(大文字小文字区別なし・単語マッチなし・正規表現なし)")
    func defaultsToAllFalseWhenUnsaved() {
        let preference = FindOptionsPreference(defaults: makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests"))

        #expect(preference.caseSensitive == false)
        #expect(preference.wholeWord == false)
        #expect(preference.useRegex == false)
    }

    /// トグルするプロパティを指す KeyPath は @MainActor 境界を跨ぐ @Test(arguments:) では
    /// Sendable 要件を満たせないため、@MainActor クロージャで包んで Sendable にする。
    struct BoolProperty: Sendable, CustomTestStringConvertible {
        let name: String
        let get: @MainActor @Sendable (FindOptionsPreference) -> Bool
        let set: @MainActor @Sendable (FindOptionsPreference) -> Void

        var testDescription: String {
            name
        }
    }

    private nonisolated static let boolProperties: [BoolProperty] = [
        BoolProperty(name: "caseSensitive", get: { $0.caseSensitive }, set: { $0.caseSensitive = true }),
        BoolProperty(name: "wholeWord", get: { $0.wholeWord }, set: { $0.wholeWord = true }),
        BoolProperty(name: "useRegex", get: { $0.useRegex }, set: { $0.useRegex = true }),
    ]

    @Test(
        "トグルした値は UserDefaults に永続化され、次のインスタンスへ引き継がれる",
        arguments: boolProperties
    )
    func togglePersistsAcrossInstances(_ property: BoolProperty) {
        let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")

        property.set(FindOptionsPreference(defaults: defaults))

        #expect(property.get(FindOptionsPreference(defaults: defaults)) == true)
    }
}
