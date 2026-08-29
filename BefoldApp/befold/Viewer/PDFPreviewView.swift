import PDFKit
import SwiftUI

/// PDF の描画面。`Data` を `PDFDocument` にして `PDFView` に描かせる。
///
/// WKWebView 側と同じく**破棄・再生成しない**。種別が変わっても面は生かしたまま
/// 重ね順で出し分ける(差し替えると白フラッシュと stale な初期倍率が出る / TASK-266)。
struct PDFPreviewView: NSViewRepresentable {
    /// 表示する PDF の生データ。PDF 以外を表示している間は nil。
    let data: Data?
    /// 内容が変わるたびに増分する世代番号。`Data` の全比較の代わりにこれで
    /// 差し替え要否を決める(50MB の Data を毎回比較しない)。
    let contentRevision: Int
    /// この文書が画面に出ているか。見えていない間の再パースを止める(ADR 0002 段 5)。
    let isVisible: Bool
    /// ファイル単位の初期倍率。1.0 = ページ幅がビューに収まる状態。
    let initialZoom: Double
    /// AppKit 側(メニューアクション)へ `PDFView` を公開するプロキシ。
    let pdfViewProxy: PDFViewProxy

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.backgroundColor = .windowBackgroundColor
        pdfViewProxy.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // 見えていない間は差し替えない。見える状態へ戻った時点で SwiftUI が最新の値で
        // 呼び直すため、抑止した更新は 1 回へ畳まれる(ViewerRenderer の isVisible と同じ)。
        guard isVisible else { return }
        guard context.coordinator.appliedRevision != contentRevision else { return }
        context.coordinator.appliedRevision = contentRevision
        // data が nil の間(PDF 以外を表示中)は文書を外す。残すと、別種別を見ている
        // 最中に PDF 面が古い文書を抱え続け、印刷が前のファイルを刷る。
        guard let data else {
            pdfView.document = nil
            return
        }
        pdfView.document = PDFDocument(data: data)
        // 文書の差し替えで倍率は既定へ戻るため、ファイル単位の値をここで入れ直す。
        pdfView.autoScales = false
        let fit = pdfView.scaleFactorForSizeToFit
        pdfView.scaleFactor = (fit > 0 ? fit : 1) * initialZoom
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 適用済みの世代番号だけを覚える箱。
    @MainActor
    final class Coordinator {
        var appliedRevision = -1
    }
}
