import AppKit
import SwiftUI

final class ViewerSplitViewController: NSSplitViewController {
    init(sidebarView: NSView, mainView: NSView) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = true
        sidebarItem.viewController.view = sidebarView

        let contentItem = NSSplitViewItem(viewController: NSViewController())
        contentItem.viewController.view = mainView

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        splitView.autosaveName = "ViewerSplitView"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
