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
        return present(sidebar: source.flatMap(makeSidebar), folder: nil, asTabOf: source)
    }

    /// フォルダーの一覧を本文に出す窓を、新しい窓として開く(`befold <ディレクトリ>` など)。
    /// 文書を持たない窓なので、空タブと同じく文書・履歴の台帳とセッション復元には載らない。
    @discardableResult
    func openFolder(_ directory: URL, sidebar: BlankTabSidebarContext) -> BlankTabWindowController {
        present(sidebar: sidebar, folder: directory, asTabOf: nil)
    }

    private func present(
        sidebar: BlankTabSidebarContext?, folder: URL?, asTabOf source: NSWindow?
    ) -> BlankTabWindowController {
        let controller = BlankTabWindowController(sidebar: sidebar, presenting: folder) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        ViewerTabGrouping.present(controller.window, asTabOf: source, placement: .end, select: true) {
            controller.showWindow(nil)
        }
        return controller
    }
}
