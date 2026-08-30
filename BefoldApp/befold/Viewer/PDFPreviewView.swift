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
        // ピンチと Ctrl+ホイールを倍率操作として受ける面。スクロールは `PDFView` に
        // 任せる(TASK-567)。レイアウト規則は PDFSurfaceLayout が単一の情報源。
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
        // **最初の 1 フレームより前に倍率を確定させる。** レイアウト任せにすると、
        // 切り替え直後の 1 フレームがフィット前の倍率で描かれ、その後に縮む過程が
        // 見える(サイドバーで .md → .pdf と送ったときの「レンダリングの経過が見える」/
        // TASK-567 のユーザー報告)。
        PDFSurfaceLayout.apply(zoom: initialZoom, to: pdfView)
        // 位置は余地が決まってからでないと入らないので面へ預け、下の同期レイアウトで
        // 入れる。余地がまだ 0 なら次のレイアウトへ持ち越される。
        pdfView.pendingRestoreFraction = scrollPositionToRestore
        // ここでレイアウトまで済ませ、倍率・位置が入った状態で最初の描画を迎える。
        pdfView.layoutSubtreeIfNeeded()
        // **最初のフレームもこの実行の中で描く。** `layoutSubtreeIfNeeded` までで
        // 倍率と位置は確定するが、実際の描画は AppKit の次の表示サイクルまで来ない。
        // 実測(2026-08-30 / 151 ページ・128KB・窓内で .md → .pdf へ切替)では、
        // レイアウト完了から最初の描画まで 12〜16ms 空いていた。`display()` で
        // 同じ実行の中へ引き取ると 0.24〜0.27ms になり、切替全体(loadContent から
        // 最初の描画まで)は 49ms → 34.7ms へ縮む。描画そのものは 5.4〜5.5ms で、
        // 待っていた時間より短い。
        pdfView.display()
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
