import AppKit
import BefoldRenderKit
import SwiftUI
import WebKit

/// バンドル同梱の Markdown ファイルを、ビューア本体と同じレンダリング経路で表示する。
///
/// ヘルプ系パネル（謝辞など）が Markdown を生テキストのまま出さないようにするための最小の器。
/// 描画は 1 回きりで、ファイル監視・ズーム・検索といったビューア本体の機能は持たない
/// （QuickLook 拡張と同じ `OneShotRenderer` の使い方）。
struct RenderedMarkdownView: NSViewRepresentable {
    /// 表示する Markdown ファイル。アプリに同梱されたリソースを想定する。
    let url: URL
    /// 読み込み・描画に失敗したときに代わりに出す文言。
    let failureMessage: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.load(url: url, failureMessage: failureMessage, into: container)
        return container
    }

    func updateNSView(_: NSView, context _: Context) {
        // 表示対象は生成時に確定する固定リソースのため、更新時にやることはない。
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// レンダラの寿命をビューに合わせて保持する。`OneShotRenderer` を都度生成すると
    /// 描画完了前に解放されて空白のまま残るため、Coordinator が持ち主になる。
    @MainActor
    final class Coordinator {
        // ヘルプ表示にリンク遷移や画像の追加読込は要らないので、QuickLook と同じく
        // ブリッジ・直接 HTML・画像埋め込みを閉じた構成で描画する。
        private let renderer = OneShotRenderer(features: .quickLookRestricted)
        private var loadTask: Task<Void, Never>?

        func load(url: URL, failureMessage: String, into container: NSView) {
            loadTask = Task { [renderer] in
                let result = await renderer.load(url: url)
                guard result.rejectReason == nil else {
                    Self.fill(container, with: Self.makeMessageView(failureMessage))
                    return
                }
                Self.fill(container, with: result.webView)
            }
        }

        deinit {
            loadTask?.cancel()
        }

        private static func makeMessageView(_ message: String) -> NSView {
            let label = NSTextField(labelWithString: message)
            label.alignment = .center
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            return label
        }

        private static func fill(_ container: NSView, with subview: NSView) {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                subview.topAnchor.constraint(equalTo: container.topAnchor),
                subview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
    }
}
