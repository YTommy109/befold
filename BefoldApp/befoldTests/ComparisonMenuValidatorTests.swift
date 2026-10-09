import AppKit
@testable import befold
import Testing

/// View メニューの比較基準項目(TASK-679)の validate。
@MainActor
struct ComparisonMenuValidatorTests {
    private final class StubSource: ViewerMenuValidationSource {
        var capabilities: ViewerCapabilities = .none
        var isSourceMode = false
        var showLineNumbers = false
        var isBookmarked = false
        var canGoBack = false
        var canGoForward = false
        var effectiveDisplayMode: ViewerDisplayMode = .rendered
        var isDiffLayoutSideBySide = false
        var isSidebarCollapsed = false
        var allowsSidebar = true
        var comparisonMenuState = ComparisonMenuState(
            current: .parentBranch, selectable: [.parentBranch, .head], isAvailable: true
        )
    }

    private func makeItem(tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: "", action: #selector(ViewerWindowController.selectComparisonTarget(_:)), keyEquivalent: ""
        )
        item.tag = tag
        return item
    }

    @Test("比較基準項目は現在の基準にだけチェックを付け、選択肢に無いスタック全体は隠す")
    func checksCurrentComparisonTargetAndHidesUnselectable() {
        let source = StubSource()
        source.comparisonMenuState = ComparisonMenuState(
            current: .head, selectable: [.parentBranch, .head], isAvailable: true
        )
        for target in GitComparisonTarget.allCases {
            let item = makeItem(tag: ComparisonTargetPresentation.menuItemTag(for: target))

            #expect(ViewerMenuValidator.validate(item, source: source))
            #expect(item.state == (target == .head ? .on : .off))
            #expect(item.isHidden == (target == .defaultBranch))
        }
    }

    @Test("比較基準項目は git 管理外では無効、タグが基準に対応しなければ無効で隠す")
    func disablesComparisonTargetOutsideGit() {
        let source = StubSource()
        source.comparisonMenuState = ComparisonMenuState(
            current: .parentBranch, selectable: [.parentBranch, .head], isAvailable: false
        )
        let item = makeItem(tag: ComparisonTargetPresentation.menuItemTag(for: .parentBranch))
        #expect(!ViewerMenuValidator.validate(item, source: source))

        let unknown = makeItem(tag: -1)
        source.comparisonMenuState = ComparisonMenuState(current: .head, selectable: [.head], isAvailable: true)
        #expect(!ViewerMenuValidator.validate(unknown, source: source))
        #expect(unknown.isHidden)
    }
}
