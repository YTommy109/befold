import AppKit
import BefoldKit
import BefoldRenderKit
import Quartz

/// QuickLook 拡張のプレビュー本体。
/// レンダリングロジックは一切持たず、対象外拡張子の早期 reject と
/// ViewerRenderer.loadOneShot の呼び出し、その結果のビュー埋め込みだけを行う。
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let renderer = ViewerRenderer()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Info.plist の QLSupportedContentTypes は UTI 単位のため、UTI が一致しても
        // befold が扱わない拡張子のファイルが渡りうる(例: public.source-code に
        // 適合するが codeExtensionLanguages に無い拡張子)。FileType の分類を
        // 単一情報源として、対象外なら QuickLook の既定のプレビューへ委ねる。
        guard FileType.quickLookSupportedExtensions.contains(url.pathExtension.lowercased()) else {
            throw CocoaError(.featureUnsupported)
        }

        renderer.rendererFeatures = .quickLookRestricted
        let result = await renderer.loadOneShot(url: url)

        if let rejectReason = result.rejectReason {
            embed(makeMessageView(rejectReason.localizedMessage))
        } else {
            embed(result.webView)
        }
    }

    /// サイズ超過・バイナリ等でコンテンツを描画しない場合の代替表示。
    private func makeMessageView(_ message: String) -> NSView {
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func embed(_ subview: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
