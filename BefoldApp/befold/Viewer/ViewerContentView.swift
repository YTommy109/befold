import BefoldKit
import BefoldRenderKit
import SwiftUI

/// プレビュー領域。**フォルダー一覧とファイルの描画面の出し分けだけ**を持つ。
///
/// 描画面そのものへの配線（レンダラへ渡す値・非対応時のオーバーレイ）は
/// `DocumentSurfaceStack` にある。判定の粒度が違うもの（フォルダー vs ファイル と、
/// どの描画面でファイルを描くか）を 1 つの View に同居させないための分割（TASK-564.6）。
struct ViewerContentView: View {
    /// 倍率・スクロール復元位置を含む、この窓のライブな表示状態。
    /// ファイル単位の保存ストア(`ZoomStore`)や窓の記憶(`WindowPresentationMemory`)は
    /// **ここへ渡さない**。渡すと body の再評価のたびに読み直すことになり、他窓が書いた値を
    /// 生きている窓が拾ってしまう(ADR 0002「文書の状態の規則」1)。
    /// 読む契機は ViewerWindowController 側の提示開始 3 箇所に限る。
    let store: ViewerStore
    let findOptionsPreference: FindOptionsPreference
    /// 見出しジャンプの設定(出発点と書き戻し口)。
    let headingJump: HeadingJumpLevelBinding
    /// ロード時に JS へ注入するソースビュー等幅フォントファミリー名。nil はシステム既定。
    let codeFontFamily: String?
    /// ロード時に JS へ注入するソースビューのコードフォントサイズ(pt)。nil は未カスタマイズ
    /// (CSS 側の calc(本文*0.75) フォールバックへ委ね、アクセシビリティ文字サイズに追従する)。
    let codeFontSizePoints: Double?
    let csvGrouping: Bool
    let csvNegativeStyle: CsvNegativeStyle
    let fileListModel: FileListModel
    /// JS 側の出来事の通知先(倍率・スクロール位置・リンク・パス解決・続きを読み込む)。
    let rendererDelegate: WeakRendererDelegate
    let onSelectFile: (URL) -> Void
    let onNavigateToFolder: (URL) -> Void
    let webViewProxy: WebViewProxy
    let pdfViewProxy: PDFViewProxy
    /// 差分のレイアウト設定。全ウィンドウ共有(差分を出すかどうかは store の表示モードが持つ)。
    let diffDisplayPreference: DiffDisplayPreference

    /// プレビューエリアが表示すべき対象。導出は FileListModel に 1 つだけ置く(ADR 0002)。
    private var previewTarget: PreviewTarget {
        fileListModel.previewTarget
    }

    var body: some View {
        // フォルダー表示でも描画面を階層に残す。差し替えにすると行を通過する
        // たびに WKWebView が破棄・再生成され、フォーカス移動が待たされる(TASK-266)。
        let folderURL = previewTarget.folderURL
        ZStack {
            DocumentSurfaceStack(
                store: store,
                isVisible: folderURL == nil,
                findOptionsPreference: findOptionsPreference,
                headingJump: headingJump,
                codeFontFamily: codeFontFamily,
                codeFontSizePoints: codeFontSizePoints,
                csvGrouping: csvGrouping,
                csvNegativeStyle: csvNegativeStyle,
                rendererDelegate: rendererDelegate,
                webViewProxy: webViewProxy,
                pdfViewProxy: pdfViewProxy,
                diffDisplayPreference: diffDisplayPreference
            )
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
}
