import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let zoomStore: ZoomStore
    let onZoomChanged: @MainActor (Double) -> Void
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
    let webViewProxy: WebViewProxy

    /// 表示中ファイルの保存倍率。ファイル切替(store.filePath 変化)で再評価され、
    /// 切替先ファイルの倍率が ViewerWebView の coordinator へ渡る。
    /// これがないと初回ファイルの倍率がウィンドウ生存中ずっと固定されてしまう。
    private var currentZoom: Double {
        guard let url = store.filePath else { return ZoomStore.defaultZoom }
        return zoomStore.zoom(for: url)
    }

    var body: some View {
        // ViewerWebView は常に生かしておき(ビュー同一性を維持)、非対応時は
        // 上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
        // 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
        VStack(spacing: 0) {
            if showTopBar {
                ViewerTopBar(store: store)
            }

            ZStack {
                ViewerWebView(
                    content: store.content,
                    fileType: store.fileType,
                    isDeleted: store.isDeleted,
                    filePath: store.filePath,
                    isSourceMode: store.isSourceMode,
                    showLineNumbers: store.showLineNumbers,
                    initialZoom: currentZoom,
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

    private var showTopBar: Bool {
        if store.isUnsupported { return false }
        if store.isSourceMode { return true }
        if case .code = store.fileType { return true }
        return false
    }
}
