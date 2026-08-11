import AppKit
import BefoldKit
import BefoldRenderKit
import Quartz
import WebKit

/// QuickLook 拡張のプレビュー本体。
/// レンダリングロジックは一切持たず、対象外拡張子の早期 reject と
/// OneShotRenderer.load の呼び出し、その結果のビュー埋め込みだけを行う。
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let renderer = OneShotRenderer(features: .quickLookRestricted)

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

        let result = await renderer.load(url: url)

        if let rejectReason = result.rejectReason {
            fill(with: makeMessageView(rejectReason.localizedMessage))
        } else {
            fill(with: result.webView)
            showRenderingIndicatorUntilIdle(of: result.webView)
        }
        // バッジは最後に載せて、描画中表示より前面に来るようにする。
        addBadge()
    }

    /// 描画が OneShotRenderer のタイムアウト内に終わらなかった場合、プレビューは
    /// 空白のまま数秒放置される。ユーザーが「表示できていない」と誤解するため、
    /// 描画中であることを明示し、完了したら取り除く。
    ///
    /// 完了判定に evaluateJavaScript を使う: markdown-it / mermaid の描画は JS の
    /// メインスレッドを占有するため、投げた評価が返ってきた時点で描画は終わっている。
    /// 既に描画が終わっていれば即座に返るため、軽いファイルでは事実上表示されない。
    private func showRenderingIndicatorUntilIdle(of webView: WKWebView) {
        let indicator = makeMessageView(
            String(localized: "quicklook.rendering", bundle: .befoldKitResources)
        )
        indicator.alphaValue = 0.7
        indicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task { @MainActor [weak indicator] in
            _ = try? await webView.evaluateJavaScript("1")
            indicator?.removeFromSuperview()
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

    private func fill(with subview: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// どの QuickLook 拡張がプレビューを担当したかを見分けるための表示。
    /// QuickLook は 1 つの UTI につき拡張を 1 つしか選ばず優先度指定の API もないため、
    /// 対象拡張子でも他の拡張(QLMarkdown / Safari / システム標準)が選ばれることがある。
    /// WebView の描画に依存しないネイティブビューとして重ねることで、
    /// 内容が空でも「befold が担当したが描画できなかった」ことを判別できる。
    /// バージョンを含めるのは、インストール済みのどのビルドが動いているかを
    /// プレビュー上で確認できるようにするため(検証時にビルドの取り違えが起きたため)。
    private func addBadge() {
        let badge = NSTextField(
            labelWithString: QuickLookBadge.text(infoDictionary: Bundle.main.infoDictionary)
        )
        badge.font = .systemFont(ofSize: 9, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 4
        background.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(badge)
        view.addSubview(background)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 5),
            badge.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -5),
            badge.topAnchor.constraint(equalTo: background.topAnchor, constant: 2),
            badge.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -2),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }
}
