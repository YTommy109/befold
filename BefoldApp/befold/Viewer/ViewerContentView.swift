import BefoldKit
import BefoldRenderKit
import SwiftUI

struct ViewerContentView: View {
    let store: ViewerStore
    let zoomStore: ZoomStore
    let scrollPositionStore: ScrollPositionStore
    let findOptionsPreference: FindOptionsPreference
    /// ロード時に JS へ注入するソースビュー等幅フォントファミリー名。nil はシステム既定。
    let codeFontFamily: String?
    /// ロード時に JS へ注入するソースビューのコードフォントサイズ(pt)。nil は未カスタマイズ
    /// (CSS 側の calc(本文*0.75) フォールバックへ委ね、アクセシビリティ文字サイズに追従する)。
    let codeFontSizePoints: Double?
    let fileListModel: FileListModel
    /// JS 側の出来事の通知先(倍率・スクロール位置・リンク・パス解決・続きを読み込む)。
    let rendererDelegate: WeakRendererDelegate
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void
    let webViewProxy: WebViewProxy
    /// 差分のレイアウト設定。全ウィンドウ共有(差分を出すかどうかは store の表示モードが持つ)。
    let diffDisplayPreference: DiffDisplayPreference

    /// 表示中ファイルの保存倍率。ファイル切替(store.filePath 変化)で再評価され、
    /// 切替先ファイルの倍率が ViewerWebView の coordinator へ渡る。
    /// これがないと初回ファイルの倍率がウィンドウ生存中ずっと固定されてしまう。
    private var currentZoom: Double {
        guard let url = store.filePath else { return ZoomStore.defaultZoom }
        return zoomStore.zoom(for: url)
    }

    /// レンダラへ渡す差分の状態。差分表示モードでなければ本文があっても差分を出さない
    /// (取得側が止まっていても、表示側でも同じ答えになるようにする)。
    private var diffState: ViewerRenderer.DiffState {
        guard store.showsDiff, let text = store.diffText else { return .none }
        return ViewerRenderer.DiffState(text: text, layout: diffDisplayPreference.layout)
    }

    private var currentScrollPosition: Double {
        guard let url = store.filePath else { return 0 }
        return scrollPositionStore.scrollPosition(for: url, mode: .init(isSourceMode: store.isSourceMode))
    }

    /// プレビューエリアが表示すべき対象。導出は FileListModel に 1 つだけ置く(ADR 0002)。
    private var previewTarget: PreviewTarget {
        fileListModel.previewTarget
    }

    var body: some View {
        // フォルダー表示でも ViewerWebView を階層に残す。差し替えにすると行を通過する
        // たびに WKWebView が破棄・再生成され、フォーカス移動が待たされる(TASK-266)。
        let folderURL = previewTarget.folderURL
        ZStack {
            filePreview(isVisible: folderURL == nil)
                .opacity(folderURL == nil ? 1 : 0)
                .accessibilityHidden(folderURL != nil)
                .allowsHitTesting(folderURL == nil)

            if let folderURL {
                FolderListingView(
                    directory: folderURL,
                    sortOrder: fileListModel.sortOrder,
                    showHiddenFiles: fileListModel.showHiddenFiles,
                    filter: fileListModel.listFilter,
                    source: fileListModel.listingSource(for: folderURL),
                    openFile: store.filePath,
                    onSelectFile: onSelectFile,
                    onNavigateToFolder: onNavigateToFolder
                )
            }
        }
    }

    /// 表示中ファイルのプレビュー。ViewerWebView は常に生かしておき(ビュー同一性を維持)、
    /// 非対応時は上に UnsupportedFileView を重ねる。テキスト↔バイナリの切替で WKWebView が
    /// 破棄・再生成されて白フラッシュや stale な initialZoom が起きるのを防ぐ。
    private func filePreview(isVisible: Bool) -> some View {
        ZStack {
            ViewerWebView(
                content: store.content,
                contentRevision: store.contentRevision,
                fileType: store.fileType,
                filePath: store.filePath,
                hasDeclaredHTMLCharset: store.hasDeclaredHTMLCharset,
                isSourceMode: store.isSourceMode,
                showLineNumbers: store.showLineNumbers,
                diffState: diffState,
                isTruncated: store.isTruncated,
                lineCount: store.displayedLineCount,
                loadFailed: store.loadFailed,
                isVisible: isVisible,
                initialZoom: currentZoom,
                codeFontFamily: codeFontFamily,
                codeFontSizePoints: codeFontSizePoints,
                scrollPositionToRestore: currentScrollPosition,
                rendererDelegate: rendererDelegate,
                findOptionsPreference: findOptionsPreference,
                webViewProxy: webViewProxy,
                rendererFeatures: .allEnabled
            )
            .opacity(store.isRejected ? 0 : 1)

            if let reason = store.rejectReason {
                UnsupportedFileView(fileURL: store.filePath, rejectReason: reason)
            } else if store.isLoading, store.content.isEmpty {
                LoadingIndicatorView()
            }
        }
    }
}
