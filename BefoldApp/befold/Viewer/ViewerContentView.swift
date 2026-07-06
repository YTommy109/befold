import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let initialZoom: Double
    let onZoomChanged: @MainActor (Double) -> Void
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
    let webViewProxy: WebViewProxy

    var body: some View {
        // ViewerWebView は常に生かしておき(ビュー同一性を維持)、非対応時は
        // 上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
        // 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
        ZStack {
            ViewerWebView(
                content: store.content,
                fileType: store.fileType,
                isDeleted: store.isDeleted,
                initialZoom: initialZoom,
                onZoomChanged: onZoomChanged,
                onOpenReference: onOpenReference,
                webViewProxy: webViewProxy
            )
            .opacity(store.isUnsupported ? 0 : 1)

            if store.isUnsupported {
                UnsupportedFileView(fileURL: store.filePath)
            }
        }
    }
}
