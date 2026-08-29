import BefoldKit
import BefoldRenderKit

/// この窓が持つ**描画面の束**と、命令をどの面へ届けるかの決定。
///
/// 窓は面を 1 枚ずつ stored property で持たない。面が増えるたびに窓の
/// stored property と配線が増えると、`ViewerWindowController`(実測 895 行、
/// 例外枠 900)が面の枚数だけ太る。束をここへ寄せ、窓は 1 本だけ持つ。
///
/// **宛先の決定はこの型の 2 メソッドだけが持つ。** メニュー・ツールバー・
/// コマンドがそれぞれ種別を見て面を選ぶ形にはしない(ADR 0002 段 2 の
/// 「条件は 1 箇所」を、能力だけでなく宛先にも適用する)。
///
/// 面が 2 枚になるのは TASK-564.1(PDF を `PDFView` で描く)。**いまは 1 枚しか無い**が、
/// 宛先を決める継ぎ目を先に 1 箇所へ作っておくことで、PDF の追加が
/// `operating(on:)` の中身だけの変更で済む。
@MainActor
final class DocumentSurfaces {
    /// SwiftUI 内部で生成される WKWebView / ViewerRenderer への弱参照ホルダー。
    /// 面そのものではなく橋渡しなので、面が増えても proxy は面ごとに 1 つ持つ。
    let web = WebViewProxy()

    private let webRenderer: any DocumentRendering

    /// - Parameter webRenderer: テスト専用シーム。渡さなければ `web` proxy を使う
    ///   `WebViewDocumentRenderer` を作る。**本番の生成経路はここ 1 箇所**で、
    ///   窓ごとに 1 個の `DocumentSurfaces` が持つ。
    init(webRenderer: (any DocumentRendering)? = nil) {
        self.webRenderer = webRenderer ?? WebViewDocumentRenderer(webViewProxy: web)
    }

    /// HTML を直接ロードして表示しているか。能力の導出(`ViewerCapabilities`)が読む。
    /// 窓が `web` proxy を直接覗く形にしないための投影。
    var isDirectHTMLMode: Bool {
        webRenderer.isDirectHTMLMode
    }

    /// **いま描いている面 1 枚**を返す。ユーザー操作(ズーム・印刷・検索・ジャンプ・
    /// スクロール位置取得)の宛先。
    ///
    /// - Parameter fileType: **描画が確定した**種別(`ViewerContentState.fileType`)を渡すこと。
    ///   提示予定の URL から導いた種別(`CurrentDocumentRef` 経由)を渡してはならない。
    ///   あちらは `ViewerStore.pendingURL` そのもので、`openFile` の入口で同期的に進む一方、
    ///   内容の着地は後になる。渡すと、切替直後の「画面には旧ファイルが出ているのに
    ///   命令は新しい面へ飛ぶ」区間ができ、命令が無言で捨てられる。
    ///
    ///   能力の導出が `supportsDiffDisplay` だけ URL 側から取り直している(TASK-338)のとは
    ///   逆向きの判断であり、意図的に揃えていない。あちらは「まだ来ていない種別で git を
    ///   起こさない」ための fail-closed なゲートで、早すぎる切替が安全側に倒れる。
    ///   宛先の決定は fail-silent なので、遅れて確定する側に合わせる。
    func operating(on fileType: FileType) -> any DocumentSurfaceOperating {
        // 面が 1 枚しか無い間は種別を見る必要が無い。PDF の面が入る TASK-564.1 で、
        // ここが唯一の分岐点になる。
        _ = fileType
        return webRenderer
    }

    /// **すべての面**。設定の反映とリネーム追随の宛先。
    /// 見えているかどうかで絞らない(理由は `DocumentSurfaceSyncing` の doc)。
    var syncingAll: [any DocumentSurfaceSyncing] {
        [webRenderer]
    }
}
