import Foundation

// MARK: - ペイロードキー(JS → Swift)

/// ペイロードキーの宣言は本体から分けている(file_length の行数上限)。
public extension ViewerBridge {
    /// postMessage のペイロードオブジェクトのキー。Swift の読み取り側(ViewerRenderer)と
    /// JS の送信側(viewer-main.js)で同じ名前を使う必要があるため、ここを単一情報源にする
    /// (JS 側との突合は ViewerBridgePayloadContractTests がソースを読んで検証する)。
    enum PayloadKey {
        /// referenceActivated のキー。
        public enum ReferenceActivated: String, CaseIterable, Sendable {
            case href
            case metaKey
            case shiftKey
        }

        /// scrollPositionChanged のキー。
        public enum ScrollPositionChanged: String, CaseIterable, Sendable {
            case position
            case mode
            /// その位置が属する文書のパス。JS が位置(scrollTop)を読むのと同じターンで
            /// 読んで載せるため、evaluateJavaScript のキューや postMessage 配達の遅延と
            /// 無関係に実 DOM の文書と一致する(Swift 側の描画済みミラーからの推定を
            /// やめた理由 = TASK-393)。文書が定まらない間(描画前)は null。
            case path
        }

        /// findOptionsChanged のキー。
        public enum FindOptionsChanged: String, CaseIterable, Sendable {
            case caseSensitive
            case wholeWord
            case useRegex
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
    /// zoomChanged は裸の数値を送るためキーを持たず、この表には登録しない。
    /// 契約テストは JS 側の全 postMessage 呼び出しを走査してこの表と突合する。
    /// 実体は `BridgeMessage.payloadKeys` の網羅 switch なので、メッセージを追加すると
    /// キー宣言を書くまでコンパイルが通らない。
    static let payloadKeysByMessageName: [String: Set<String>] = Dictionary(
        uniqueKeysWithValues: BridgeMessage.allCases.compactMap { message in
            message.payloadKeys.map { (message.rawValue, $0) }
        }
    )
}
