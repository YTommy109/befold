import BefoldKit
import BefoldRenderKit
import SwiftUI

/// 表示中ファイルの**描画面**とその上に重なるオーバーレイを組み立てる層。
///
/// 描画サーフェスへの配線（どの値をどの面へ渡すか）と、非対応・読み込み中の
/// オーバーレイをここに閉じる。`ViewerContentView` はフォルダー一覧との
/// 出し分けだけを持ち、レンダラの入力を 1 つも知らない。
///
/// 分けた理由は行数ではない（切り出す前の `ViewerContentView` は 111 行だった）。
/// **描画面が 2 枚になる**（TASK-564.1 で PDF を `PDFView` で描く）と、
/// フォルダー一覧との出し分けと同じ場所に 2 枚目のサーフェス配線が並び、
/// 「どちらを見せるか」の判定が 2 種類（フォルダー vs ファイル / WebView vs PDF）
/// 同居する。判定の粒度が違うものを 1 つの View に置かないための分割（TASK-564.6）。
///
/// **サーフェスは破棄・再生成しない。** 非対応時も読み込み中も面は生かしたまま
/// 上に重ねる。差し替えにすると行を通過するたびに描画面が作り直され、
/// 白フラッシュと stale な初期倍率が出る（TASK-266）。
struct DocumentSurfaceStack: View {
    /// 倍率・スクロール復元位置を含む、この窓のライブな表示状態。
    /// ファイル単位の保存ストア（`ZoomStore`）や窓の記憶（`WindowPresentationMemory`）は
    /// **ここへ渡さない**。渡すと body の再評価のたびに読み直すことになり、他窓が書いた値を
    /// 生きている窓が拾ってしまう（ADR 0002「文書の状態の規則」1）。
    let store: ViewerStore
    /// この窓が開く対象の種別。**内容が着地するまでのあいだだけ**、どの面を
    /// 用意するかの判断に使う(`isOpeningPDF`)。着地後は `contentState.fileType` が
    /// 唯一の情報源になるので、この値が古くなっても影響しない。
    let openingFileType: FileType
    /// この文書が画面に出ているか。フォルダー一覧を重ねている間は false になる。
    /// 見えていない文書の再描画を止めるために各サーフェスへ配る（ADR 0002 段 5）。
    let isVisible: Bool
    let findOptionsPreference: FindOptionsPreference
    /// 見出しジャンプの設定（出発点と書き戻し口）。
    let headingJump: HeadingJumpLevelBinding
    /// ロード時に JS へ注入するソースビュー等幅フォントファミリー名。nil はシステム既定。
    let codeFontFamily: String?
    /// ロード時に JS へ注入するソースビューのコードフォントサイズ(pt)。nil は未カスタマイズ。
    let codeFontSizePoints: Double?
    let csvGrouping: Bool
    let csvNegativeStyle: CsvNegativeStyle
    /// JS 側の出来事の通知先（倍率・スクロール位置・リンク・パス解決・続きを読み込む）。
    let rendererDelegate: WeakRendererDelegate
    let webViewProxy: WebViewProxy
    /// PDF の面への橋渡し。面ごとに 1 つで、束(`DocumentSurfaces`)が持つものを受け取る。
    let pdfViewProxy: PDFViewProxy
    /// PDF の面と窓のあいだの受け渡し(倍率の通知・回転の要求)。
    let pdfActions: PDFSurfaceActions
    /// 差分のレイアウト設定。全ウィンドウ共有（差分を出すかどうかは store の表示モードが持つ）。
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

    /// いま PDF を描いているか。**この判定はどの面を見せるかにしか使わない。**
    /// 命令の宛先(ズーム・印刷・スクロール位置)は `DocumentSurfaces.operating(on:)` が
    /// 同じ `contentState.fileType` から決める(ADR 0009)。
    private var showsPDF: Bool {
        store.contentState.fileType == .pdf
    }

    /// WKWebView の面を階層へ入れるか。**PDF だけを開いた窓では作らない**(TASK-564.7)。
    ///
    /// PDF は `PDFView` が描くので viewer.html は要らないが、面を素直に並べると
    /// WKWebView の生成と viewer バンドル(816KB)の読み込みが窓ごとに走る。実測では
    /// 窓を開いてから PDF が出るまで約 320ms のうち、生成だけで 51ms、その後の
    /// メインスレッドの詰まりが 172ms あった。
    ///
    /// **これは生成の遅延であって破棄ではない。** 一度作った面は以後ずっと残す
    /// (TASK-266 の「行を通過するたびに作り直さない」はそのまま守る)。既に作ってあるか
    /// どうかは proxy が持つ参照がそのまま表すので、別の記憶を新設しない。
    private var needsWebSurface: Bool {
        webViewProxy.webView != nil || !isOpeningPDF
    }

    /// 開こうとしている / 開いている文書が PDF か。
    ///
    /// **内容が着地するまでは `openingFileType`(窓が開く対象の種別)で判断する。**
    /// 着地前の `contentState.fileType` は既定のままなので、それだけで判断すると
    /// 必ず WKWebView を作ってしまい目的を果たさない。`ViewerStore.pendingFileType` も
    /// 使えない——分割ビューの構築(= この View の最初の評価)は
    /// `openInitialDocument` より**先**に走るため、そこではまだ既定値のままになる
    /// (実測: PDF を開いても `makeNSView` が呼ばれた)。
    ///
    /// 宛先の決定(`DocumentSurfaces.operating(on:)`)が提示予定の種別を**使わない**のとは
    /// 逆の判断だが、性質が違う——あちらは fail-silent(命令が無言で捨てられる)、
    /// こちらは fail-safe(判断を外しても面が少し遅れて作られるだけ)。
    private var isOpeningPDF: Bool {
        store.contentState.filePath == nil ? openingFileType == .pdf : showsPDF
    }

    var body: some View {
        ZStack {
            if needsWebSurface {
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
                    csvGrouping: csvGrouping,
                    csvNegativeStyle: csvNegativeStyle,
                    scrollPositionToRestore: store.scrollPositionToRestore,
                    rendererDelegate: rendererDelegate,
                    findOptionsPreference: findOptionsPreference,
                    headingJump: headingJump,
                    webViewProxy: webViewProxy,
                    rendererFeatures: .allEnabled
                )
                .opacity(store.contentState.isRejected || showsPDF ? 0 : 1)
                .allowsHitTesting(!showsPDF)
            }

            // PDF の面。WebView と同じく差し替えず、重ね順で出し分ける。
            // 見せていない間は data に nil を渡し、面が古い文書を抱えたままにしない。
            PDFPreviewView(
                data: showsPDF ? store.contentState.data : nil,
                contentRevision: store.contentState.contentRevision,
                isVisible: isVisible,
                initialZoom: store.zoom,
                scrollPositionToRestore: store.scrollPositionToRestore,
                rotation: store.pdfRotation,
                pdfViewProxy: pdfViewProxy,
                onZoomChanged: pdfActions.onZoomChanged
            )
            .opacity(store.contentState.isRejected || !showsPDF ? 0 : 1)
            .allowsHitTesting(showsPDF)

            // 回転コントロール。PDF の面と**同じ条件**で出す(条件は 1 箇所)。
            if showsPDF, !store.contentState.isRejected {
                PDFRotationOverlay(onRotate: pdfActions.onRotate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if let reason = store.contentState.rejectReason {
                UnsupportedFileView(fileURL: store.contentState.filePath, rejectReason: reason)
            } else if store.contentState.showsLoadingIndicator {
                LoadingIndicatorView()
            }
        }
    }
}
