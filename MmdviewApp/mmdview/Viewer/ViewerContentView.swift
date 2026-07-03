import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let initialZoom: Double
    let onZoomChanged: @MainActor (Double) -> Void
    let webViewProxy: WebViewProxy

    var body: some View {
        ViewerWebView(
            content: store.content,
            fileType: store.fileType,
            isDeleted: store.isDeleted,
            initialZoom: initialZoom,
            onZoomChanged: onZoomChanged,
            webViewProxy: webViewProxy
        )
    }
}
