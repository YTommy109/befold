import AppKit
import SwiftUI

/// 既存ウィンドウのサイドバー開閉を、ジェネリック型パラメータを消して操作するためのプロトコル。
/// CLI の `--sidebar`/`--no-sidebar` をパス無し起動で既存ウィンドウへ適用する際に使う。
@MainActor
protocol SidebarCollapsible: AnyObject {
    func setSidebarCollapsed(_ collapsed: Bool)
}

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    private let sidebarItem: NSSplitViewItem
    private var didForceInitialCollapse = false
    private let initialCollapsed: Bool
    private let onCollapsedChange: (Bool) -> Void

    init(
        sidebar: Sidebar, content: Content, initialCollapsed: Bool = true,
        onCollapsedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.initialCollapsed = initialCollapsed
        self.onCollapsedChange = onCollapsedChange
        sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: sidebar))
        super.init(nibName: nil, bundle: nil)

        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: NSHostingController(rootView: content))

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        // ディバイダー位置(サイドバー幅)を起動をまたいで永続化する。
        // この autosave は開閉状態も復元するため、開閉だけは
        // viewWillAppear で明示的に決める(initialCollapsed が呼び出し側の解決結果)
        splitView.autosaveName = "ViewerSplitView"
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // autosave の復元が開閉状態も引き継ぐため、初回表示の直前に必ず確定させる。
        // 開閉状態(記憶の引き継ぎ・CLI からの強制表示など)の解決は呼び出し側が行い、
        // ここでは initialCollapsed をそのまま適用するだけにする。
        // タブ切替や最小化復帰でも viewWillAppear は呼ばれるため、初回に限定する
        guard !didForceInitialCollapse else { return }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = initialCollapsed
    }

    override func toggleSidebar(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        super.toggleSidebar(sender)
        onCollapsedChange(sidebarItem.isCollapsed)
        if wasCollapsed, !sidebarItem.isCollapsed {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = view.window
                else { return }
                window.makeFirstResponder(
                    sidebarItem.viewController.view
                )
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension ViewerSplitViewController: SidebarCollapsible {
    /// 望む開閉状態と現在が異なるときだけ toggleSidebar を再利用して切り替える。
    /// これにより状態永続化(onCollapsedChange)とフォーカス移動の挙動を一本化する。
    func setSidebarCollapsed(_ collapsed: Bool) {
        guard sidebarItem.isCollapsed != collapsed else { return }
        toggleSidebar(nil)
    }
}
