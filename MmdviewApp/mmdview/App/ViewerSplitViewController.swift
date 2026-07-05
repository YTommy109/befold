import AppKit
import SwiftUI

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    init(sidebar: Sidebar, content: Content) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: sidebar))
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = true

        let contentItem = NSSplitViewItem(viewController: NSHostingController(rootView: content))

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.autosaveName = "ViewerSplitView"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
