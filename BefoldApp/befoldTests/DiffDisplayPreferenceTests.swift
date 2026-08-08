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

    @Test("既定はインライン")
    func defaultsToInline() {
        let preference = DiffDisplayPreference(defaults: makeDefaults(#function))

        #expect(preference.layout == .inline)
    }

    @Test("レイアウトが永続化される")
    func persistsLayout() {
        let defaults = makeDefaults(#function)
        let preference = DiffDisplayPreference(defaults: defaults)

        preference.layout = .sideBySide

        #expect(DiffDisplayPreference(defaults: defaults).layout == .sideBySide)
    }

    @Test("壊れたレイアウト保存値はインラインへ落ちる")
    func fallsBackToInlineForUnknownLayout() {
        let defaults = makeDefaults(#function)
        defaults.set("bogus", forKey: "SourceDiffLayout")

        #expect(DiffDisplayPreference(defaults: defaults).layout == .inline)
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
