import AppKit
import BefoldKit

/// 文書を持たない窓の寿命を管理する。⌘T の空タブと、フォルダーの一覧を本文に出す窓
/// (ディレクトリを開いた窓)。文書・履歴の台帳とセッション復元には載らない。
@MainActor
final class BlankTabCoordinator {
    private(set) var controllers: [BlankTabWindowController] = []
    private let makeSidebar: (URL, SidebarInheritance.Seed) -> BlankTabSidebarContext

    /// - Parameter makeSidebar: サイドバーのルートにするディレクトリと引き継ぐ種から、サイドバーの材料を作る。
    init(makeSidebar: @escaping (URL, SidebarInheritance.Seed) -> BlankTabSidebarContext) {
        self.makeSidebar = makeSidebar
    }

    /// ⌘T。起点の窓がサイドバーを持てば、その位置から始める(持たなければサイドバー無し)。
    @discardableResult
    func open(relativeTo sourceWindow: NSWindow?) -> BlankTabWindowController {
        let source = Self.tabSource(sourceWindow)
        let sidebar = source.flatMap { window in
            SidebarInheritance.currentDirectory(of: window).map { directory in
                makeSidebar(
                    directory,
                    SidebarInheritance.seed(from: window, opensAsTab: true, replacing: nil, opening: nil)
                )
            }
        }
        return present(sidebar: sidebar, folder: nil, asTabOf: source, select: true)
    }

    /// フォルダーの一覧を本文に出す窓を開く(`befold <ディレクトリ>`・Finder、サイドバーの
    /// フォルダー行の「新しいタブ/ウィンドウで開く」)。ファイルは開かない(ADR 0013 決定 5)。
    ///
    /// 同じフォルダーの一覧を出している窓があれば、文書の窓と同じ表
    /// (`ViewerWindowOpenPolicy.reusableWindow`)で再利用する。照合は本文の意図で行い、
    /// サイドバーのルートは見ない。新しいタブは起点のタブとして背面に開く(文書と同じ)。
    /// CLI の表示オプションは再利用した窓にも当てる(黙って捨てない / TASK-413)。
    @discardableResult
    func openFolder(
        _ directory: URL, options: CLIOpenOptions, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?
    ) -> BlankTabWindowController {
        NSApplication.shared.activate()
        let key = directory.normalizedPathKey
        let showing = controllers.filter { $0.presentationIntent.target.folderURL?.normalizedPathKey == key }
        let folderWindow: BlankTabWindowController
        if let existing = ViewerWindowOpenPolicy.reusableWindow(
            from: showing, disposition: disposition, relativeTo: sourceWindow
        ) {
            existing.window?.makeKeyAndOrderFront(nil)
            folderWindow = existing
        } else {
            let source = disposition == .newTab ? Self.tabSource(sourceWindow) : nil
            let sidebar = makeSidebar(directory, ViewerDisplayOptionsApplier.folderSeed(options))
            folderWindow = present(sidebar: sidebar, folder: directory, asTabOf: source, select: source == nil)
        }
        ViewerDisplayOptionsApplier.apply(options, toFolderWindow: folderWindow)
        return folderWindow
    }

    /// タブを足せる起点。スライド窓などタブに合流しない窓なら nil(新しい窓になる)。
    private static func tabSource(_ window: NSWindow?) -> NSWindow? {
        window is ViewerDocumentWindow && window?.tabbingMode != .disallowed ? window : nil
    }

    private func present(
        sidebar: BlankTabSidebarContext?, folder: URL?, asTabOf source: NSWindow?, select: Bool
    ) -> BlankTabWindowController {
        let controller = BlankTabWindowController(sidebar: sidebar, presenting: folder) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        ViewerTabGrouping.present(controller.window, asTabOf: source, placement: .end, select: select) {
            controller.showWindow(nil)
        }
        return controller
    }
}
