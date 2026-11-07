import AppKit

/// 文書をまだ持たないタブの寿命を管理する。文書・履歴の台帳には登録しない。
@MainActor
final class BlankTabCoordinator {
    private(set) var controllers: [BlankTabWindowController] = []
    private let makeSidebar: (NSWindow) -> BlankTabSidebarContext?

    /// - Parameter makeSidebar: 起点の窓からサイドバーの材料を作る。起点がサイドバーを持たなければ nil。
    init(makeSidebar: @escaping (NSWindow) -> BlankTabSidebarContext?) {
        self.makeSidebar = makeSidebar
    }

    @discardableResult
    func open(relativeTo sourceWindow: NSWindow?) -> BlankTabWindowController {
        let source = sourceWindow is ViewerDocumentWindow
            && sourceWindow?.tabbingMode != .disallowed ? sourceWindow : nil
        let controller = BlankTabWindowController(sidebar: source.flatMap(makeSidebar)) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        ViewerTabGrouping.present(controller.window, asTabOf: source, placement: .end, select: true) {
            controller.showWindow(nil)
        }
        return controller
    }
}
