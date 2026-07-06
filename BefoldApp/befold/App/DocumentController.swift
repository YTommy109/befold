import AppKit

/// Recent Documents メニューからのファイルオープンを AppDelegate に委譲する。
final class DocumentController: NSDocumentController {
    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        AppDelegate.shared?.openViewer(for: url)
        completionHandler(nil, false, nil)
    }
}
