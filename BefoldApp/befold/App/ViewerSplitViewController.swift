import AppKit
import SwiftUI

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    private let sidebarItem: NSSplitViewItem
    private var didForceInitialCollapse = false

    init(sidebar: Sidebar, content: Content) {
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
        // viewWillAppear で常に閉じた状態へ強制する
        splitView.autosaveName = "ViewerSplitView"
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // autosave の復元が開閉状態も引き継ぐため、初回表示の直前に必ず閉じる。
        // (新規ウィンドウ・タブは常にサイドバーが閉じた状態で開く仕様)
        // タブ切替や最小化復帰でも viewWillAppear は呼ばれるため、初回に限定する
        guard !didForceInitialCollapse else { return }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
