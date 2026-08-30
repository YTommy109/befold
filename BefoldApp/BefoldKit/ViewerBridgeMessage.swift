import Foundation

/// JS → Swift の postMessage メッセージ（受信方向の契約）。
///
/// ハンドラの登録側(`ViewerWebViewFactory`)と受信側のルーティング(`BridgeMessageRouter`)を
/// ここから導出し、両者が同期を要求される 2 つのリストに分かれるのを防ぐ
/// (登録したのにルーティングを書き忘れて無反応、を型で潰す)。
///
/// 送信方向(Swift → JS のスクリプト組み立て)は `ViewerBridge` が持つ。関心の向きが逆で、
/// この型だけが `BridgeMessageRouter` と 1 対 1 に対応するため別の型に分けている。
/// ここの文字列を変更する場合は viewer.html 側の定義とあわせて変更すること
/// (整合性は ViewerBridgeContractTests がソースを読んで検証する)。
public enum ViewerBridgeMessage: String, CaseIterable, Sendable {
    /// JS 側で全体ズーム倍率が変わったとき。
    /// payload: { zoom: Double, path: String | null }
    /// path は倍率を読んだ時点で DOM に出ていた文書のパス(renderDocPathScript で予告した値)。
    case zoomChanged

    /// JS 側で検索トグル(大文字小文字区別・単語マッチ・正規表現)が変わったとき。
    /// payload: { caseSensitive: Bool, wholeWord: Bool, useRegex: Bool }
    case findOptionsChanged

    /// JS 側で文書内ジャンプの見出しレベルのトグルが変わったとき。
    /// payload: { levels: [String] }（`["h1","h2","h3"]` 形式。
    /// 空配列は「3 つとも OFF」で、これも保存すべき正当な値）
    case jumpLevelsChanged

    /// リンクやパス参照がクリックされたとき。
    /// 修飾キーの解釈は Swift 側(OpenDisposition)が行うため、JS は押下状態のみ送る。
    /// payload: { href: String, metaKey: Bool, shiftKey: Bool }
    case referenceActivated

    /// リンクやパス参照の上で ctrl+クリック(右クリック)されたとき。
    /// Swift 側が NSMenu を表示する。payload: { href: String }
    case referenceContextMenu

    /// JS 側「続きを読み込む」ボタン押下時。payload: なし(空オブジェクト)。
    case loadMoreLines

    /// JS 側が検出したパス参照の解決を要求するとき。payload: { paths: [String] }
    case resolveReferences

    /// ホストの対話的ブリッジ(`RendererFeatures.allowsInteractiveBridging`)を要するか。
    /// false のホスト(QuickLook 拡張等の静的 1 回描画)では、これが true のものを
    /// そもそも登録しない(多層防御: XSS が postMessage を直接呼んでも Swift へ届かない)。
    public var requiresInteractiveBridging: Bool {
        switch self {
        case .zoomChanged, .findOptionsChanged, .jumpLevelsChanged:
            false
        case .referenceActivated, .referenceContextMenu, .loadMoreLines, .resolveReferences:
            true
        }
    }

    /// JS がオブジェクトとして送るペイロードのキー集合。裸の値を送る場合は nil。
    /// 契約テストはこの表と JS 側の postMessage 呼び出しを突合するため、
    /// メッセージを追加するとこの switch がコンパイルエラーになって登録漏れを防ぐ。
    var payloadKeys: Set<String>? {
        switch self {
        case .zoomChanged: Set(PayloadKey.ZoomChanged.allCases.map(\.rawValue))
        case .findOptionsChanged: Set(PayloadKey.FindOptionsChanged.allCases.map(\.rawValue))
        case .jumpLevelsChanged: Set(PayloadKey.JumpLevelsChanged.allCases.map(\.rawValue))
        case .referenceActivated: Set(PayloadKey.ReferenceActivated.allCases.map(\.rawValue))
        case .referenceContextMenu: Set(PayloadKey.ReferenceContextMenu.allCases.map(\.rawValue))
        case .loadMoreLines: []
        case .resolveReferences: Set(PayloadKey.ResolveReferences.allCases.map(\.rawValue))
        }
    }

    /// postMessage のペイロードオブジェクトのキー。Swift の読み取り側(ViewerRenderer)と
    /// JS の送信側(viewer-main.js)で同じ名前を使う必要があるため、ここを単一情報源にする
    /// (JS 側との突合は ViewerBridgePayloadContractTests がソースを読んで検証する)。
    public enum PayloadKey {
        /// referenceActivated のキー。
        public enum ReferenceActivated: String, CaseIterable, Sendable {
            case href
            case metaKey
            case shiftKey
        }

        /// zoomChanged のキー。
        public enum ZoomChanged: String, CaseIterable, Sendable {
            case zoom
            /// その倍率が属する文書のパス。JS が倍率を読むのと同じターンで読んで
            /// 載せるため、evaluateJavaScript のキューや postMessage 配達の遅延と
            /// 無関係に実 DOM の文書と一致する(Swift 側の描画済みミラーからの推定を
            /// やめた理由 = TASK-393)。切替直後に配達された通知が切替先のキーを
            /// 汚すのを防ぐ(TASK-391)。文書が定まらない間(描画前)は null。
            case path
        }

        /// findOptionsChanged のキー。
        public enum FindOptionsChanged: String, CaseIterable, Sendable {
            case caseSensitive
            case wholeWord
            case useRegex
        }

        /// jumpLevelsChanged のキー。
        public enum JumpLevelsChanged: String, CaseIterable, Sendable {
            case levels
        }

        /// resolveReferences のキー。
        public enum ResolveReferences: String, CaseIterable, Sendable {
            case paths
        }

        /// referenceContextMenu のキー。
        public enum ReferenceContextMenu: String, CaseIterable, Sendable {
            case href
        }
    }

    /// メッセージ名 → JS がオブジェクトとして送るペイロードのキー集合。
    /// 契約テストは JS 側の全 postMessage 呼び出しを走査してこの表と突合する。
    /// 実体は `payloadKeys` の網羅 switch なので、メッセージを追加すると
    /// キー宣言を書くまでコンパイルが通らない。
    public static let payloadKeysByMessageName: [String: Set<String>] = Dictionary(
        uniqueKeysWithValues: ViewerBridgeMessage.allCases.compactMap { message in
            message.payloadKeys.map { (message.rawValue, $0) }
        }
    )
}
