@testable import BefoldKit
import Testing

struct HiddenFileRuleTests {
    @Test("ドット始まりの構成要素だけを隠しと判定する")
    func detectsDotPrefixedComponent() {
        #expect(HiddenFileRule.isHidden(component: ".config"))
        #expect(HiddenFileRule.isHidden(component: ".git"))
        #expect(!HiddenFileRule.isHidden(component: "config"))
        #expect(!HiddenFileRule.isHidden(component: "a.md")) // 途中のドットは隠しではない
    }

    @Test("相対パスのどこかにドット始まりの構成要素があれば隠しとみなす")
    func detectsHiddenComponentAnywhereInRelativePath() {
        #expect(HiddenFileRule.containsHiddenComponent(inRelativePath: ".config/app.toml"))
        #expect(HiddenFileRule.containsHiddenComponent(inRelativePath: "src/.hidden/x.md"))
        #expect(!HiddenFileRule.containsHiddenComponent(inRelativePath: "src/docs/x.md"))
    }
}
