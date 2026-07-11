import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let zoomStore: ZoomStore
    let scrollPositionStore: ScrollPositionStore
    let findOptionsPreference: FindOptionsPreference
    let onZoomChanged: @MainActor (Double) -> Void
    let onScrollPositionChanged: @MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void
    let onOpenReference: @MainActor (_ href: String, _ isExternal: Bool, _ newWindow: Bool) -> Void
    let webViewProxy: WebViewProxy

    /// 表示中ファイルの保存倍率。ファイル切替(store.filePath 変化)で再評価され、
    /// 切替先ファイルの倍率が ViewerWebView の coordinator へ渡る。
    /// これがないと初回ファイルの倍率がウィンドウ生存中ずっと固定されてしまう。
    private var currentZoom: Double {
        guard let url = store.filePath else { return ZoomStore.defaultZoom }
        return zoomStore.zoom(for: url)
    }

    private var currentScrollPosition: Double {
        guard let url = store.filePath else { return 0 }
        let mode: ViewerBridge.ViewMode = store.isSourceMode ? .source : .rendered
        return scrollPositionStore.scrollPosition(for: url, mode: mode)
    }

    var body: some View {
        // ViewerWebView は常に生かしておき(ビュー同一性を維持)、非対応時は
        // 上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
        // 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
        VStack(spacing: 0) {
            if store.showsCodeContent {
                ViewerTopBar(store: store)
            }

            ZStack {
                ViewerWebView(
                    content: store.content,
                    fileType: store.fileType,
                    filePath: store.filePath,
                    isSourceMode: store.isSourceMode,
                    showLineNumbers: store.showLineNumbers,
                    initialZoom: currentZoom,
                    scrollPositionToRestore: currentScrollPosition,
                    onScrollPositionChanged: onScrollPositionChanged,
                    onZoomChanged: onZoomChanged,
                    onOpenReference: onOpenReference,
                    findOptionsPreference: findOptionsPreference,
                    webViewProxy: webViewProxy
                )
                .opacity(store.isUnsupported ? 0 : 1)

                if store.isUnsupported {
                    UnsupportedFileView(fileURL: store.filePath)
                }
            }
        }
    }
}
