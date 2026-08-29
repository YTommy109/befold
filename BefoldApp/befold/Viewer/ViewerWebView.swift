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
    /// HTML の charset 宣言(BOM/meta charset)有無。HTML 直接ロードモードで
    /// webView.load(正規化文字列を注入)/loadFileURL(WebKit に委ねる)の分岐に使う。
    let hasDeclaredHTMLCharset: Bool?
    /// ソース表示中かどうか。true の間 HTML ファイルも viewer.html でレンダリングする。
    let isSourceMode: Bool
    /// ソース表示中に行番号を表示するかどうか。
    let showLineNumbers: Bool
    /// ソース表示へ重ねる git 差分（本文とレイアウト）。差分を出さないときは `.none`。
    let diffState: ViewerRenderer.DiffState
    /// ファイルの一部だけを読み込んでいる(段階読み込み中)かどうか。
    let isTruncated: Bool
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    let lineCount: Int
    /// 直近のチャンク読込がエラーで打ち切られたかどうか。
    let loadFailed: Bool
    /// この文書が画面に出ているか。フォルダー一覧を重ねている間は false になる。
    /// 見えていない文書の再描画(監視対象ファイルの更新に伴う全再レイアウト)を止めるために使う。
    /// 見える状態へ戻った時点で SwiftUI が最新の値で updateNSView を呼び直すため、
    /// 抑止した更新は自動的に 1 回へ畳まれる(ADR 0002 段 5)。
    let isVisible: Bool
    /// ロード時に JS へ注入するファイル毎の初期倍率。
    let initialZoom: Double
    /// **いま提示中の文書を描いているのがこの面か。** 面が 2 枚あるので、
    /// 宛先でない面へファイル単位の値（倍率・復元位置）を流し込まない。
    /// 流し込むと、PDF へ切り替える瞬間に PDF の倍率が**まだ見えている
    /// Markdown へ**当たり、切り替わる直前にちらつく（TASK-567 の実測）。
    /// 判定は `DocumentSurfaceStack` が持つ 1 つの述語から配る。
    let ownsDocument: Bool
    /// ロード時に JS へ注入するソースビュー等幅フォントファミリー名。nil はシステム既定。
    let codeFontFamily: String?
    /// ロード時に JS へ注入するソースビューのコードフォントサイズ(pt)。nil は未カスタマイズ
    /// (CSS 側の calc(本文*0.75) フォールバックへ委ね、アクセシビリティ文字サイズに追従する)。
    let codeFontSizePoints: Double?
    let csvGrouping: Bool
    let csvNegativeStyle: CsvNegativeStyle
    /// render() 呼び出し前に JS へ注入するスクロール復元位置。
    let scrollPositionToRestore: Double
    /// JS 側の出来事(倍率・スクロール位置・リンク・パス解決・続きを読み込む)の通知先。
    /// SwiftUI View はウィンドウ階層越しに通知先へ強参照を持つと循環するため weak で運ぶ。
    let rendererDelegate: WeakRendererDelegate
    /// 検索バーの3トグル(大文字小文字区別・単語マッチ・正規表現)の永続化ストア。
    let findOptionsPreference: FindOptionsPreference
    /// 見出しジャンプの設定(この窓の出発点と書き戻し口)。読み取り API を持たない
    /// 記録口なので、窓が保存値を読み直す経路は構造的に作れない(ADR 0002「窓の状態」)。
    let headingJump: HeadingJumpLevelBinding
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
        renderer.diffState = diffState

        renderer.headingJumpLevelRecording = headingJump.recording
        let webView = renderer.makeWebView(
            initialZoom: initialZoom, findOptionsPreference: findOptionsPreference,
            codeFontFamily: codeFontFamily, codeFontSizePoints: codeFontSizePoints,
            csvGrouping: csvGrouping, csvNegativeStyle: csvNegativeStyle,
            headingJumpLevels: headingJump.initialLevels
        )
        renderer.webViewProxy = webViewProxy
        webViewProxy.webView = webView
        // AppKit 側(rename の追随など)が描画状態へ届くための逆向きの橋渡し(weak)。
        webViewProxy.renderer = renderer

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let renderer = context.coordinator
        renderer.findOptionsPreference = findOptionsPreference
        renderer.headingJumpLevelRecording = headingJump.recording
        if ownsDocument {
            renderer.initialPageZoom = initialZoom
            renderer.scrollPositionToRestore = scrollPositionToRestore
        }
        renderer.rendererFeatures = rendererFeatures
        renderer.diffState = diffState
        // 設定の反映(倍率・フォント・検索オプション)は隠れていても通す。止めると
        // フォルダーを見ている間の設定変更が取り残される。重い再描画だけを renderer 側で止める。
        renderer.isVisible = isVisible
        renderer.updateContent(
            content,
            contentRevision: contentRevision,
            fileType: fileType,
            filePath: filePath,
            hasDeclaredHTMLCharset: hasDeclaredHTMLCharset,
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
