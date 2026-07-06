import Foundation
@testable import befold
import Testing

@Suite
struct PathKeyedDictionaryTests {
    @Test
    func valueIsNilWhenUnsaved() {
        let dict = PathKeyedDictionary<Double>(
            defaults: makeIsolatedDefaults(prefix: "PathKeyedDictionaryTests"),
            key: "Test"
        )

        #expect(dict.value(for: URL(fileURLWithPath: "/files/a.mmd")) == nil)
    }

    @Test
    func setValueRoundTrips() {
        let dict = PathKeyedDictionary<Double>(
            defaults: makeIsolatedDefaults(prefix: "PathKeyedDictionaryTests"),
            key: "Test"
        )
        let url = URL(fileURLWithPath: "/files/a.mmd")

        dict.setValue(1.5, for: url)

        #expect(dict.value(for: url) == 1.5)
    }

    @Test("rename で旧キーの値が新キーへ移り旧キーは消える")
    func migrateValueMovesValueToNewKey() {
        let dict = PathKeyedDictionary<Double>(
            defaults: makeIsolatedDefaults(prefix: "PathKeyedDictionaryTests"),
            key: "Test"
        )
        let old = URL(fileURLWithPath: "/files/old.mmd")
        let new = URL(fileURLWithPath: "/files/new.mmd")
        dict.setValue(1.75, for: old)

        dict.migrateValue(from: old, to: new)

        #expect(dict.value(for: new) == 1.75)
        #expect(dict.value(for: old) == nil)
    }

    @Test("旧キーに保存値がない migrate は新キーの既存値を上書きしない")
    func migrateValueWithoutSavedValueIsNoop() {
        let dict = PathKeyedDictionary<Double>(
            defaults: makeIsolatedDefaults(prefix: "PathKeyedDictionaryTests"),
            key: "Test"
        )
        let old = URL(fileURLWithPath: "/files/old.mmd")
        let new = URL(fileURLWithPath: "/files/new.mmd")
        dict.setValue(1.5, for: new)

        dict.migrateValue(from: old, to: new)

        #expect(dict.value(for: new) == 1.5)
    }
}
