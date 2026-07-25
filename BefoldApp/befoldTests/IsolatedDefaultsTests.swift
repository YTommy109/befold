import BefoldTestSupport
import Foundation
import Testing

/// makeIsolatedDefaults がディスクに触れず、呼び出しごとに独立していることを検証する。
@Suite struct IsolatedDefaultsTests {
    @Test("呼び出しごとに独立した領域を返す")
    func eachCallGetsIndependentStorage() {
        let first = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")
        let second = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")

        first.set("value", forKey: "key")

        #expect(first.string(forKey: "key") == "value")
        #expect(second.string(forKey: "key") == nil)
    }

    @Test("型付きの読み書きが往復する")
    func typedValuesRoundTrip() {
        let defaults = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")

        defaults.set(true, forKey: "bool")
        defaults.set(42, forKey: "int")
        defaults.set(1.5, forKey: "double")
        defaults.set("text", forKey: "string")
        defaults.set(["a", "b"], forKey: "stringArray")
        defaults.set(["k": 1], forKey: "dictionary")
        defaults.set(Data([0x01, 0x02]), forKey: "data")

        #expect(defaults.bool(forKey: "bool"))
        #expect(defaults.integer(forKey: "int") == 42)
        #expect(defaults.double(forKey: "double") == 1.5)
        #expect(defaults.string(forKey: "string") == "text")
        #expect(defaults.stringArray(forKey: "stringArray") == ["a", "b"])
        #expect(defaults.dictionary(forKey: "dictionary")?["k"] as? Int == 1)
        #expect(defaults.data(forKey: "data") == Data([0x01, 0x02]))
    }

    @Test("未設定のキーは既定値を返す")
    func missingKeysReturnDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")

        #expect(defaults.object(forKey: "absent") == nil)
        #expect(defaults.string(forKey: "absent") == nil)
        #expect(defaults.bool(forKey: "absent") == false)
        #expect(defaults.integer(forKey: "absent") == 0)
    }

    @Test("削除したキーは取り出せなくなる")
    func removedKeysDisappear() {
        let defaults = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")
        defaults.set("value", forKey: "key")

        defaults.removeObject(forKey: "key")

        #expect(defaults.object(forKey: "key") == nil)
    }

    @Test("nil の代入はキーの削除として扱う")
    func settingNilRemovesKey() {
        let defaults = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")
        defaults.set("value", forKey: "key")

        defaults.set(nil, forKey: "key")

        #expect(defaults.object(forKey: "key") == nil)
    }

    /// 本題: 独立領域を作っても ~/Library/Preferences に plist を残さない。
    /// 以前は "<接頭辞>-<UUID>.plist" が毎回作られ、削除経路がなかった。
    @Test("plist をディスクに作らない")
    func doesNotCreatePreferencesFile() {
        let prefix = "IsolatedDefaultsProbe-\(UUID().uuidString)"
        let preferencesDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Preferences")

        let defaults = makeIsolatedDefaults(prefix: prefix)
        defaults.set("value", forKey: "key")
        _ = defaults.synchronize()

        let leaked = (try? FileManager.default.contentsOfDirectory(atPath: preferencesDir))?
            .filter { $0.hasPrefix(prefix) } ?? []
        #expect(leaked.isEmpty)
    }

    /// 独立領域への書き込みが実際の共有スイートへ漏れないことを確認する。
    /// 型付きセッターが setObject:forKey: を経由しない実装だった場合、
    /// 利用者の設定を汚しうるため、書き込み側を明示的に確認しておく。
    @Test("実際の共有スイートへ書き込まない")
    func doesNotWriteToTheSharedSuite() throws {
        let key = "IsolatedDefaultsProbeKey-\(UUID().uuidString)"
        let defaults = makeIsolatedDefaults(prefix: "IsolatedDefaultsTests")

        defaults.set(true, forKey: key)
        defaults.set(42, forKey: key + "-int")
        defaults.set("text", forKey: key + "-string")

        let shared = try #require(UserDefaults(suiteName: "com.degino.befold"))
        #expect(shared.object(forKey: key) == nil)
        #expect(shared.object(forKey: key + "-int") == nil)
        #expect(shared.object(forKey: key + "-string") == nil)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        #expect(UserDefaults.standard.object(forKey: key + "-int") == nil)
        #expect(UserDefaults.standard.object(forKey: key + "-string") == nil)
    }
}
