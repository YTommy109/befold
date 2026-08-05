@testable import befold
import BefoldKit
import Foundation
import Testing

@MainActor
struct DiffDisplayPreferenceTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "DiffDisplayPreferenceTests.\(name)")!
        defaults.removePersistentDomain(forName: "DiffDisplayPreferenceTests.\(name)")
        return defaults
    }

    @Test("既定は OFF・インライン")
    func defaultsToDisabledInline() {
        let preference = DiffDisplayPreference(defaults: makeDefaults(#function), isAvailable: true)

        #expect(preference.isEnabled == false)
        #expect(preference.layout == .inline)
    }

    @Test("ON とレイアウトが永続化される")
    func persistsEnabledAndLayout() {
        let defaults = makeDefaults(#function)
        let preference = DiffDisplayPreference(defaults: defaults, isAvailable: true)

        preference.isEnabled = true
        preference.layout = .sideBySide

        let restored = DiffDisplayPreference(defaults: defaults, isAvailable: true)
        #expect(restored.isEnabled)
        #expect(restored.layout == .sideBySide)
    }

    /// 機能が無効なビルドでは切り替える手段が露出しないため、保存値 ON でも OFF として読む。
    /// 保存値そのものは消さない(dev ビルドへ戻れば ON で復帰する)。
    @Test("機能が無効なら保存値 ON でも OFF として読む")
    func readsDisabledWhenFeatureUnavailable() {
        let defaults = makeDefaults(#function)
        DiffDisplayPreference(defaults: defaults, isAvailable: true).isEnabled = true

        #expect(DiffDisplayPreference(defaults: defaults, isAvailable: false).isEnabled == false)
        // 保存値は残っている
        #expect(DiffDisplayPreference(defaults: defaults, isAvailable: true).isEnabled)
    }

    @Test("壊れたレイアウト保存値はインラインへ落ちる")
    func fallsBackToInlineForUnknownLayout() {
        let defaults = makeDefaults(#function)
        defaults.set("bogus", forKey: "SourceDiffLayout")

        #expect(DiffDisplayPreference(defaults: defaults, isAvailable: true).layout == .inline)
    }
}

struct ViewerBridgeDiffScriptTests {
    @Test("差分本文をエスケープして setDiff へ渡す")
    func escapesDiffText() {
        let script = ViewerBridge.diffScript("+let s = \"</script>\"\n")

        #expect(script.hasPrefix("setDiff("))
        #expect(!script.contains("</script>"))
        #expect(script.contains("\\n"))
    }

    @Test("差分が無ければ null を渡して解除する")
    func passesNullWhenNoDiff() {
        #expect(ViewerBridge.diffScript(nil) == "setDiff(null)")
    }

    @Test("レイアウトを JS のレイアウト名で渡す")
    func passesLayoutName() {
        #expect(ViewerBridge.diffLayoutScript(.inline) == "setDiffLayout('inline')")
        #expect(ViewerBridge.diffLayoutScript(.sideBySide) == "setDiffLayout('side-by-side')")
    }
}
