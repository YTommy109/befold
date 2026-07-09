import AppKit
import SwiftUI

/// SwiftUI の List が内部生成する NSTableView への参照を得るための橋渡し。
/// 行コンテンツの背後に透明な NSView を挿し込み、superview を辿って
/// 最も近い NSTableView を探す(#144)。
/// viewDidMoveToSuperview は直近の親(AppKitPlatformViewHost)がまだウィンドウの
/// 実ツリーに繋がっていない段階で発火するため、辿っても見つからない。
/// ウィンドウに接続された後に発火する viewDidMoveToWindow で辿る必要がある。
struct SidebarTableViewLocator: NSViewRepresentable {
    let onResolve: (NSTableView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ResolvingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ResolvingView: NSView {
        var onResolve: ((NSTableView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var current = superview
            while let view = current {
                if let tableView = view as? NSTableView {
                    onResolve?(tableView)
                    return
                }
                current = view.superview
            }
        }
    }
}
