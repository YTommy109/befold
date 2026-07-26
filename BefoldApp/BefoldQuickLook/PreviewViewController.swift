import AppKit
import BefoldKit
import OSLog
import Quartz

/// QuickLook 拡張のプレビュー本体。
/// TASK-72.1 時点では「appex ホストから BefoldKit のリソースが解決できるか」を
/// 実機確認するための最小実装で、解決結果をテキスト表示するだけに留める。
/// 実際の描画(loadOneShot 呼び出し)は TASK-72.5 で入れる。
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let bundle = Bundle.befoldKitResources
        let viewerHTML = bundle.url(forResource: "viewer", withExtension: "html")
        let summary = """
        file: \(url.lastPathComponent)
        befoldKitResources: \(bundle.bundlePath)
        viewer.html: \(viewerHTML?.path ?? "NOT FOUND")
        """
        Logger(subsystem: "com.degino.befold.quicklook", category: "probe")
            .notice("\(summary, privacy: .public)")
        label.stringValue = summary
    }
}
