import BefoldKit
import Foundation

/// 描画面のナビゲーション事象を受け取り、readiness ゲートと直接 HTML モードへ振り分ける。
///
/// ViewerRenderer から切り出してあるのは、JS からの postMessage を受ける
/// BridgeMessageRouter と同じ理由——framework の delegate 面という関心が
/// 「描画状態の管理」と独立しているため。受信・分類までがこの型の責務で、
/// 復帰の中身(倍率の当て直し・viewer.html の読み直し)は DirectHTMLModeController と
/// ViewerReadinessGate が持つ。ここへ判断ロジックを溜めないこと。
///
/// renderer は **weak** で持つ。「renderer がこの型を所有するので寿命は必ず renderer が
/// 長い」は、コールバックが同期で届く限りしか成り立たない。`async` な @objc delegate
/// メソッドはランタイムが Task を作って `self`(= このコーディネータ)だけを強参照するため、
/// サスペンド中に renderer だけが解放されうる。unowned のままだと再開時にトラップする
/// (ReferenceResolutionQueue の TASK-448 と同型)。
///
/// あわせて `surfaceShouldNavigate` は **同期で返す**。WebKit 側で completion-handler 版の
/// デリゲートを選んでいるのと対になっていて、サスペンドが無ければ renderer が消える窓
/// そのものが生まれない。ここへ受信メソッドを足すときも同じ理由で同期を選ぶこと
/// （翻訳は `WebKitSurfaceEventBridge` が行う）。
@MainActor
final class ViewerNavigationCoordinator: SurfaceNavigationObserver {
    private weak var renderer: ViewerRenderer?

    init(renderer: ViewerRenderer) {
        self.renderer = renderer
    }

    func surfaceDidFinishLoad() {
        guard let renderer else { return }
        // **surface を要るのは倍率の当て直しだけ。** ここを guard へ併合すると、
        // surface が未設定のときに markReady まで飛ばされ、runWhenReady に積まれた
        // 描画要求が全部落ちて窓が白いままになる（倍率が当たらないより重い故障）。
        if let surface = renderer.surface {
            renderer.directHTML.applyPendingZoom(to: surface)
        }
        renderer.pageZoom.applyIfReady(assumingReady: true)
        renderer.readiness.markReady()
    }

    func surfaceDidFailLoad() {
        handleNavigationFailure()
    }

    /// 初回の HTML ロード（loadFileURL）は常に許可する。viewer.html モードではそれ以外の
    /// ナビゲーションを全てキャンセルする(JS 側がリンクを処理する)。直接 HTML モードでは
    /// リンククリック(.linkActivated)のみ directHTMLLinkPolicy で分類して処理する。
    ///
    /// renderer が既に無ければ表示先が無いので `.cancel` を返す。
    func surfaceShouldNavigate(_ request: SurfaceNavigationRequest) -> SurfaceNavigationDecision {
        guard let renderer, let surface = renderer.surface else {
            // 初回の viewer.html ロードがここで弾かれると準備完了が永久に来ない(TASK-607)。
            RenderDiagnostics.log("navigation: shouldNavigate を cancel (renderer/surface が未設定)")
            return .cancel
        }
        return renderer.directHTML.decidePolicy(surface: surface, request: request)
    }

    private func handleNavigationFailure() {
        guard let renderer else { return }
        renderer.directHTML.discardPendingZoom()
        if renderer.directHTML.isActive, let surface = renderer.surface {
            // 削除起因の失敗は呼び出し側がウィンドウを閉じる等の対応をするため、
            // ここでは viewer.html へ戻すだけでよい
            renderer.directHTML.exit(surface: surface) {}
        } else {
            renderer.readiness.flushPending()
        }
    }
}
