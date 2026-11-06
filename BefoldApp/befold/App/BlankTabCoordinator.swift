import AppKit

/// 文書をまだ持たないタブの寿命を管理する。文書・履歴の台帳には登録しない。
@MainActor
final class BlankTabCoordinator {
    private(set) var controllers: [BlankTabWindowController] = []

    @discardableResult
    func open(relativeTo sourceWindow: NSWindow?) -> BlankTabWindowController {
        let controller = BlankTabWindowController { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        let source = sourceWindow is ViewerDocumentWindow
            && sourceWindow?.tabbingMode != .disallowed ? sourceWindow : nil
        ViewerTabGrouping.present(controller.window, asTabOf: source, placement: .end, select: true) {
            controller.showWindow(nil)
        }
        return controller
    }
}
