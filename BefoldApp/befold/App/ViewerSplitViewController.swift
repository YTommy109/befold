import AppKit
import SwiftUI

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    private let sidebarItem: NSSplitViewItem
    private var didForceInitialCollapse = false
    private let forceSidebarVisible: Bool
    private let collapsedHandleView = CollapsedSidebarHandleView()

    init(sidebar: Sidebar, content: Content, forceSidebarVisible: Bool = false) {
        self.forceSidebarVisible = forceSidebarVisible
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
        // viewWillAppear で明示的に決める(forceSidebarVisible があれば開く)
        splitView.autosaveName = "ViewerSplitView"

        collapsedHandleView.translatesAutoresizingMaskIntoConstraints = false
        collapsedHandleView.onActivate = { [weak self] in
            self?.toggleSidebar(nil)
        }
        view.addSubview(collapsedHandleView)
        NSLayoutConstraint.activate([
            collapsedHandleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collapsedHandleView.topAnchor.constraint(equalTo: view.topAnchor),
            collapsedHandleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collapsedHandleView.widthAnchor.constraint(equalToConstant: 8),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // autosave の復元が開閉状態も引き継ぐため、初回表示の直前に必ず確定させる。
        // (新規ウィンドウ・タブは通常サイドバーが閉じた状態で開く仕様。
        //  forceSidebarVisible が true の場合のみ開いた状態にする。CLI 経由で
        //  フォルダーを開いたときに、フォルダーを閲覧していることを一目で
        //  分かるようにするため)
        // タブ切替や最小化復帰でも viewWillAppear は呼ばれるため、初回に限定する
        guard !didForceInitialCollapse else {
            syncCollapsedHandleVisibility()
            return
        }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = !forceSidebarVisible
        syncCollapsedHandleVisibility()
    }

    private func syncCollapsedHandleVisibility() {
        let shouldHide = !sidebarItem.isCollapsed
        if collapsedHandleView.isHidden != shouldHide {
            collapsedHandleView.isHidden = shouldHide
        }
    }

    override func toggleSidebar(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        super.toggleSidebar(sender)
        // アニメーション完了(splitViewDidResizeSubviews)を待たず即座に反映するため明示的に呼んでいる
        syncCollapsedHandleVisibility()
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

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        syncCollapsedHandleVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
