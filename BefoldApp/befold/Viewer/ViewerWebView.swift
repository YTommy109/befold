import BefoldKit
import BefoldRenderKit
import SwiftUI
import WebKit

/// WKWebView で Mermaid / Markdown コンテンツをレンダリングする NSViewRepresentable。
/// WKWebView の構成・render 評価などドライバ本体は BefoldRenderKit.ViewerRenderer に
/// 委譲し、本体は SwiftUI とのブリッジ役に徹する。
struct ViewerWebView: NSViewRepresentable {
    let content: String
    /// content が変わるたびに増分する世代番号。ViewerRenderer は再描画要否の判定に
    /// content 全文比較でなくこれを使い、文字列の重複保持を避ける。
    let contentRevision: Int
    let fileType: FileType
    /// レンダリング対象のファイルパス。HTML ファイルは loadFileURL による直接ロードに使う。
    let filePath: URL?
    /// ソース表示中かどうか。true の間 HTML ファイルも viewer.html でレンダリングする。
    let isSourceMode: Bool
    /// ソース表示中に行番号を表示するかどうか。
    let showLineNumbers: Bool
    /// ファイルの一部だけを読み込んでいる(段階読み込み中)かどうか。
    let isTruncated: Bool
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    let lineCount: Int
    /// 直近のチャンク読込がエラーで打ち切られたかどうか。
    let loadFailed: Bool
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    let scrollPositionToRestore: Double
    /// JS 側でスクロール位置が変わったときに呼ばれる。(position, mode)
    let onScrollPositionChanged: @MainActor (_ position: Double, _ mode: ViewerBridge.ViewMode) -> Void
    /// JS 側で倍率が変わったときに呼ばれる。
    let onZoomChanged: @MainActor (Double) -> Void
    /// JS 側「続きを読み込む」押下時に呼ばれ、次チャンクと更新後の表示状態を非同期で返す。
    let onLoadMoreLines: @MainActor () async -> LoadMoreLinesResult?
    /// リンクやパス参照がアクティベートされたときに呼ばれる。
    /// パラメータ: href, newWindow
    let onOpenReference: @MainActor (_ href: String, _ newWindow: Bool) -> Void
    /// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)の永続化ストア。
    let findOptionsPreference: FindOptionsPreference
    /// AppKit 側（メニューアクション）へ WKWebView を公開するプロキシ。
    let webViewProxy: WebViewProxy
    /// 直接 HTML モード・相対画像埋め込みの有効/無効を切り替えるフラグ。
    /// アプリ本体は `.allEnabled`(既定挙動)を渡す。
    let rendererFeatures: RendererFeatures

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let renderer = context.coordinator
        renderer.findOptionsPreference = findOptionsPreference
        renderer.onLoadMoreLines = onLoadMoreLines
        renderer.onZoomChanged = onZoomChanged
        renderer.onOpenReference = onOpenReference
        renderer.onScrollPositionChanged = onScrollPositionChanged
        renderer.rendererFeatures = rendererFeatures

        let webView = renderer.makeWebView(initialZoom: initialZoom, findOptionsPreference: findOptionsPreference)
        renderer.webViewProxy = webViewProxy
        webViewProxy.webView = webView

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let renderer = context.coordinator
        renderer.onZoomChanged = onZoomChanged
        renderer.onScrollPositionChanged = onScrollPositionChanged
        renderer.onOpenReference = onOpenReference
        renderer.onLoadMoreLines = onLoadMoreLines
        renderer.findOptionsPreference = findOptionsPreference
        renderer.initialPageZoom = initialZoom
        renderer.scrollPositionToRestore = scrollPositionToRestore
        renderer.rendererFeatures = rendererFeatures
        renderer.updateContent(
            content,
            contentRevision: contentRevision,
            fileType: fileType,
            filePath: filePath,
            isSourceMode: isSourceMode,
            showLineNumbers: showLineNumbers,
            truncation: ViewerRenderer.TruncationState(
                isTruncated: isTruncated, lineCount: lineCount, failed: loadFailed
            )
        )
    }

    func makeCoordinator() -> ViewerRenderer {
        ViewerRenderer()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ViewerRenderer) {
        coordinator.dismantle(nsView)
    }
}
