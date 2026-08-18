import AppKit
@testable import befold
import Testing

/// Help > キーボードショートカット に並ぶセクション(TASK-503)。
@Suite
@MainActor
struct HelpShortcutSectionsTests {
    @Test("メニュー由来のセクションに続けて、非メニュー由来の 3 セクションが並ぶ")
    func sectionsFollowMenuThenNonMenu() {
        MenuShortcutCatalog.snapshot = [
            ShortcutSection(title: "File", entries: [ShortcutEntry(title: "Open", key: "⌘O")]),
        ]
        defer { MenuShortcutCatalog.snapshot = [] }

        let titles = HelpShortcutSections.all(isDocumentJumpEnabled: true).map(\.title)

        #expect(titles.first == "File")
        #expect(titles.count == 4)
        #expect(titles.dropFirst() == [
            ViewerShortcutCatalog.section(isDocumentJumpEnabled: true).title,
            SidebarShortcutCatalog.section.title,
            QuickOpenShortcutCatalog.section.title,
        ][...])
    }

    @Test("非メニュー由来のセクションは項目を持つ")
    func nonMenuSectionsAreNotEmpty() {
        MenuShortcutCatalog.snapshot = []
        let sections = HelpShortcutSections.all(isDocumentJumpEnabled: true)

        #expect(sections.count == 3)
        for section in sections {
            #expect(!section.entries.isEmpty, "\(section.title) が空")
            #expect(!section.title.isEmpty)
        }
    }
}
