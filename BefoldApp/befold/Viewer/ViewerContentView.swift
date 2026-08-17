import BefoldKit
import BefoldRenderKit
import SwiftUI

struct ViewerContentView: View {
    /// 倍率・スクロール復元位置を含む、この窓のライブな表示状態。
    /// ファイル単位の保存ストア(`ZoomStore` / `ScrollPositionStore`)は**ここへ渡さない**。
    /// 渡すと body の再評価のたびに保存値を読み直すことになり、他窓が書いた値を
    /// 生きている窓が拾ってしまう(ADR 0002「文書の状態の規則」1)。
    /// 保存値を読む契機は ViewerWindowController 側の提示開始 3 箇所に限る。
    let store: ViewerStore
    let findOptionsPreference: FindOptionsPreference
    /// 見出しジャンプの設定(出発点と書き戻し口)。
    let headingJump: HeadingJumpLevelBinding
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

    /// レンダラへ渡す差分の状態。差分表示モードでなければ本文があっても差分を出さない
    /// (取得側が止まっていても、表示側でも同じ答えになるようにする)。
    private var diffState: ViewerRenderer.DiffState {
        guard store.showsDiff else { return .none }
        switch store.diffContent {
        case .unavailable: return .none
        case .pending: return .pending
        case let .diff(text): return ViewerRenderer.DiffState(text: text, layout: diffDisplayPreference.layout)
        }
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
                    openFile: store.contentState.filePath,
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
                content: store.contentState.content,
                contentRevision: store.contentState.contentRevision,
                fileType: store.contentState.fileType,
                filePath: store.contentState.filePath,
                hasDeclaredHTMLCharset: store.contentState.hasDeclaredHTMLCharset,
                isSourceMode: store.isSourceMode,
                showLineNumbers: store.showLineNumbers,
                diffState: diffState,
                isTruncated: store.contentState.isTruncated,
                lineCount: store.contentState.displayedLineCount,
                loadFailed: store.contentState.loadFailed,
                isVisible: isVisible,
                initialZoom: store.zoom,
                codeFontFamily: codeFontFamily,
                codeFontSizePoints: codeFontSizePoints,
                scrollPositionToRestore: store.scrollPositionToRestore,
                rendererDelegate: rendererDelegate,
                findOptionsPreference: findOptionsPreference,
                headingJump: headingJump,
                webViewProxy: webViewProxy,
                rendererFeatures: .allEnabled
            )
            .opacity(store.contentState.isRejected ? 0 : 1)

            if let reason = store.contentState.rejectReason {
                UnsupportedFileView(fileURL: store.contentState.filePath, rejectReason: reason)
            } else if store.contentState.isLoading, store.contentState.content.isEmpty {
                LoadingIndicatorView()
            }
        }
    }
}
