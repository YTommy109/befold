import AppKit
@testable import befold
import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// 既存ウィンドウへの表示オプション適用規則そのものの検証。
///
/// openViewer 経由の経路疎通は ViewerWindowManagerDisplayOverridesTests が見ている。
/// こちらは「指定が無いフィールドに触らない」「開閉の優先順位」という規則を、
/// 開く経路を通さずに直接固定する(規則を壊しても経路テストは既定値どうしの一致で
/// 通ってしまう組み合わせがあるため)。
@Suite
@MainActor
struct ViewerDisplayOptionsApplierTests {
    private let file = URL(fileURLWithPath: "/mock/first.mmd")

    /// viewerSortOrder は未指定でも既定値(.foldersFirst)を返すため、指定の有無を
    /// sortOrder の nil で見ないと、無関係なオプション指定のたびに並び順が既定へ戻る。
    @Test("並び順の指定が無ければ、現在の並び順を書き換えない")
    func applyKeepsSortOrderWhenUnspecified() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ApplierSortOrder")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)
        controller.fileListModel.sortOrder = .alphabetical

        ViewerDisplayOptionsApplier.apply(
            CLIOpenOptions(showLineNumbers: true), to: controller, forceSidebarVisible: false
        )

        #expect(controller.fileListModel.sortOrder == .alphabetical)
        #expect(controller.store.showLineNumbers)
    }

    @Test("サイドバーは CLI の明示指定がフォルダーオープンの強制表示より優先される")
    func applyPrefersExplicitSidebarOptionOverForcedVisibility() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "ApplierSidebar")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.controllers[file.normalizedPathKey]?.first)

        ViewerDisplayOptionsApplier.apply(
            CLIOpenOptions(showSidebar: false), to: controller, forceSidebarVisible: true
        )

        #expect(fixture.perFileState.sidebar.isCollapsed(for: file) == true)
    }
}
