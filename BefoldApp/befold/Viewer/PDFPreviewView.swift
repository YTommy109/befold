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
    /// 検索の状態。**文書を差し替えたら結果を捨てる**ために受け取る(TASK-570)。
    /// 前の文書の位置を指す `PDFSelection` を抱えたまま次へ送ると、別の文書へ飛ぶ。
    let pdfFind: PDFFindModel
    /// 面の中で完結する倍率操作(ピンチ・Ctrl+ホイール)の通知先。
    /// メニュー経由の倍率変更はここを通らない(コマンド側が返り値で伝える)。
    let onZoomChanged: (Double) -> Void

    func makeNSView(context: Context) -> ZoomingPDFView {
        // ピンチと Ctrl+ホイールを倍率操作として受ける面。スクロールは `PDFView` に
        // 任せる(TASK-567)。表示設定と配線は面の init が済ませているので、
        // ここで設定し忘れた面が出回ることはない(TASK-574.1)。
        let pdfView = ZoomingPDFView(frame: .zero)
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
        // 差し替えの順序(文書 → 回転 → 倍率 → レイアウト → 位置)は面が持つ。
        // ここは「新しい入力が来た」ことを伝えるだけで、順序をこちらに書かない
        // (TASK-574.1)。data が nil の間は文書を外す——残すと、別種別を見ている
        // 最中に PDF 面が古い文書を抱え続け、印刷が前のファイルを刷る。
        pdfView.present(
            document: data.flatMap { PDFDocument(data: $0) },
            rotation: rotation,
            zoom: initialZoom,
            scrollFraction: scrollPositionToRestore
        )
        // 差し替えた後に呼ぶ。前の文書の一致は行き先が無い。
        pdfFind.documentChanged()
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
