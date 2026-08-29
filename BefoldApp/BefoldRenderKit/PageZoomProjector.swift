import BefoldKit
import WebKit

/// ファイル毎の初期倍率を viewer.js へ投影する。望む倍率(`desired`)と適用済みの記録
/// (`applied`)を 1 型へ集め、記録の書き込み入口を型の中に閉じる。
///
/// 生成時のユーザースクリプト(atDocumentStart)に焼き込むだけでは、ウィンドウの生成が
/// 表示対象の確定より先に走ったときに既定倍率のまま取り残される。値の変化と
/// viewer.html の準備完了の双方で適用し直し、「状態の投影」として扱う(ADR 0002 / TASK-270)。
///
/// `applied` は「同じ倍率を何度も評価しない」ためのキャッシュなので、viewer.js が
/// 居なくなる操作(直接 HTML モードへの遷移・viewer.html の読み直し)のたびに無効化が
/// 要る。無効化の入口を `invalidateApplied()` の 1 つに限るのは、`rendered` ミラーを
/// `recordRendered` に絞ってあるのと同じ理由(TASK-514)。
///
/// renderer はこの型を所有するため、寿命は必ず renderer が長い(unowned)。
@MainActor
final class PageZoomProjector {
    private unowned let renderer: ViewerRenderer

    /// 呼び出し側から渡される、ファイル毎の初期倍率。HTML 直接ロード時の pageZoom 適用にも使う。
    ///
    /// **代入しただけでは適用しない。** ホストはファイルを切り替えた時点で
    /// 新しいファイルの倍率を流し込むが、その瞬間に画面へ出ているのはまだ前の
    /// ファイルである（面の宛先は「描画が確定した種別」で切り替わる /
    /// `DocumentSurfaces.operating(on:)`）。ここで即座に当てると、**切り替わる前の
    /// ファイルの倍率が変わってから**新しいファイルが出る、というちらつきになる
    /// （TASK-567 の実測。PDF への切り替えで顕著だが、種別によらず起きる）。
    ///
    /// 適用の契機は「その文書が実際に描かれるとき」——**描き直しを伴う**内容の更新
    /// (`ViewerRenderer.updateContent` で `UpdatePlan` が `.skip` 以外)・
    /// viewer.html の準備完了・直接 HTML からの復帰の 3 つ。倍率と内容が同じ
    /// 同期区間で入るので、中間状態が見えない。
    ///
    /// **`.skip` を除くのが要点。** ホストの状態が変わるたびに `updateContent` は
    /// 呼ばれるが、切り替え直後のそれは前のファイルの内容に対する `.skip` である。
    var desired: Double = 1.0

    /// viewer.js へ適用済みの倍率。同じ値を何度も評価しないための記録。
    private(set) var applied: Double?

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    /// 適用済みの記録を捨て、次の機会に当て直させる。viewer.js が居なくなる操作
    /// (直接 HTML モードへの遷移・viewer.html の読み直し)の際に必ず呼ぶこと。
    func invalidateApplied() {
        applied = nil
    }

    /// 現在の `desired` を viewer.js へ適用する。viewer.html の準備前・
    /// HTML 直接ロード中(viewer.js が無い)・同じ値を適用済みのときは何もしない。
    /// - Parameter assumingReady: didFinish の中からは ready 確定前に呼ぶため true を渡す。
    func applyIfReady(assumingReady: Bool = false) {
        guard assumingReady || renderer.readiness.isReady else { return }
        guard !renderer.directHTML.isActive, let webView = renderer.webView else { return }
        guard applied != desired else { return }
        applied = desired
        webView.evaluateJavaScript(ViewerBridge.applyZoomScript(desired))
    }
}
