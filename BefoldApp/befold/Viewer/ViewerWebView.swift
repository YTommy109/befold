import BefoldKit
import BefoldRenderKit
import SwiftUI
import WebKit

/// SwiftUI View から ViewerRenderer の通知先を weak で運ぶ箱。
/// View(struct)が通知先を直接強参照すると、通知先 → ウィンドウ → ホスティングビュー → View
/// という所有の輪が閉じてしまうため、参照の弱さをここに閉じ込める。
struct WeakRendererDelegate {
    weak var value: (any ViewerRendererDelegate)?

    init(_ value: (any ViewerRendererDelegate)?) {
        self.value = value
    }
}

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
    /// ロード時に JS へ注入するソースビュー等幅フォントファミリー名。nil はシステム既定。
    let codeFontFamily: String?
    /// ロード時に JS へ注入するソースビューのコードフォントサイズ(pt)。
    let codeFontSizePoints: Double
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    let scrollPositionToRestore: Double
    /// JS 側の出来事(倍率・スクロール位置・リンク・パス解決・続きを読み込む)の通知先。
    /// SwiftUI View はウィンドウ階層越しに通知先へ強参照を持つと循環するため weak で運ぶ。
    let rendererDelegate: WeakRendererDelegate
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
        // 通知先は 1 度結び付ければよい(weak なので更新サイクルごとの張り直しは不要)。
        renderer.delegate = rendererDelegate.value
        renderer.rendererFeatures = rendererFeatures

        let webView = renderer.makeWebView(
            initialZoom: initialZoom, findOptionsPreference: findOptionsPreference,
            codeFontFamily: codeFontFamily, codeFontSizePoints: codeFontSizePoints
        )
        renderer.webViewProxy = webViewProxy
        webViewProxy.webView = webView

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let renderer = context.coordinator
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
