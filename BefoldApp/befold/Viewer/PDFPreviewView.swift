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
    /// ファイル単位の初期倍率。1.0 = ページ全体がビューに収まる状態。
    let initialZoom: Double
    /// この窓が覚えている表示位置(0…1)。文書を差し替えた直後に復元する。
    /// web の面と同じ値・同じ記憶(`WindowPresentationMemory`)を使う。
    let scrollPositionToRestore: Double
    /// この窓が覚えている回転角(0 / 90 / 180 / 270)。文書を差し替えた直後に合わせる。
    let rotation: Int
    /// AppKit 側(メニューアクション)へ `PDFView` を公開するプロキシ。
    let pdfViewProxy: PDFViewProxy
    /// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)の通知先。
    /// メニュー経由の倍率変更はここを通らない(コマンド側が返り値で伝える)。
    let onZoomChanged: (Double) -> Void

    func makeNSView(context: Context) -> ZoomingPDFView {
        // ホイールをページ送りへ振り替える面(TASK-564.2)。レイアウト規則は
        // PDFSurfaceLayout が単一の情報源。
        let pdfView = ZoomingPDFView()
        PDFSurfaceLayout.configure(pdfView)
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.onZoomChanged = onZoomChanged
        pdfViewProxy.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: ZoomingPDFView, context: Context) {
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
        // 回転は倍率より先に合わせる(縦横比が変わるとフィット倍率も変わるため)。
        PDFSurfaceLayout.apply(rotation: rotation, to: pdfView)
        // **倍率と位置はここで描き込まない。** ファイル単位の倍率と復元したい位置を
        // 面へ預け、レイアウトが落ち着いた 1 回で両方入れる(`ZoomingPDFView.layout`)。
        // 直接入れると、ページの寸法が確定するまでのあいだに倍率と位置が数回ずつ
        // 動き、開いた瞬間・戻ってきた瞬間のちらつきになる(TASK-567)。
        pdfView.zoom = initialZoom
        pdfView.pendingRestoreFraction = scrollPositionToRestore
        pdfView.needsLayout = true
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
