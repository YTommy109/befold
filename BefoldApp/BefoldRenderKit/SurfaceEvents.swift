import AppKit
import Foundation

/// 描画面で起きたリンク遷移の要求。
///
/// `WKNavigationAction` から**実際に読んでいる 3 つだけ**を写した値
/// （着手時の実測。他のプロパティはこの層が一度も参照していない）。WebKit の型を
/// 上の層へ持ち込まないための入れ物で、遷移の可否判断はこれだけで足りる。
public struct SurfaceNavigationRequest {
    /// 遷移の種類。
    ///
    /// 再読み込みは文書のホストへ戻す。ブラウザの再読み込みをそのまま通すと、
    /// viewer.html の DOM とレンダラの描画済みミラーが食い違う。
    public enum Kind: Sendable {
        /// リンクのクリック。開き方を修飾キーから決める。
        case linkActivated
        /// プログラムからのロード（初回の `loadLocalFile` / `loadHTML`）。
        case programmatic
        /// 文書の再読み込み。WebKit の遷移は止め、ホストの読み込み経路へ委譲する。
        case reload
        /// それ以外（フォーム送信・戻る/進む）。この層は通さない。
        case otherInteraction
    }

    public let kind: Kind
    public let url: URL?
    /// クリック時の修飾キー。開き方（今の窓 / 別タブ / 新規窓）の解釈に使う。
    public let modifiers: NSEvent.ModifierFlags

    public init(kind: Kind, url: URL?, modifiers: NSEvent.ModifierFlags) {
        self.kind = kind
        self.url = url
        self.modifiers = modifiers
    }
}

/// 遷移を通すか止めるか。WebKit の `WKNavigationActionPolicy` は `.download` も持つが、
/// この層は使っていないので 2 値に絞ってある。
public enum SurfaceNavigationDecision {
    case allow
    case cancel
}

/// 描画面のロード進行とリンク遷移を受け取る口。
///
/// **可否の判断は同期で返す。** WebKit 側の完了ハンドラ方式に合わせてあるのは、
/// そこが意図的な選択だから——非同期にするとサスペンド中に描画状態の持ち主が
/// 解放されうる窓が生まれる（`ViewerNavigationCoordinator` の doc を参照）。
/// この口を `async` にすると、その判断を実装側から壊せてしまう。
@MainActor
public protocol SurfaceNavigationObserver: AnyObject {
    /// ロードが完了した。
    func surfaceDidFinishLoad()
    /// ロードが失敗した。理由は区別しない（この層の対応が同じため）。
    func surfaceDidFailLoad()
    /// 遷移してよいか。**同期で返すこと。**
    func surfaceShouldNavigate(_ request: SurfaceNavigationRequest) -> SurfaceNavigationDecision
}

/// JS からのブリッジメッセージを受け取る口。
///
/// `name` と `body` しか渡さないのは、この層が `WKScriptMessage` から実際に
/// 読んでいるのがその 2 つだけだから（実測）。`body` が `Any` なのは JS から来る
/// 生の値そのもので、解釈は受け手が行う。
@MainActor
public protocol SurfaceBridgeMessageObserver: AnyObject {
    func surfaceDidReceiveBridgeMessage(name: String, body: Any)
}
