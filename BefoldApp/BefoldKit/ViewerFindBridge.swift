import Foundation

/// 検索バー(Swift → JS)のブリッジ契約を集約する。
///
/// `ViewerBridge` の extension ではなく**兄弟の型**にしてある。extension はファイルを
/// 分けても型グループの行数には合算されるため、責務を分けたことにならない
/// (`ViewerCsvBridge` と同じ方針)。JS 側の定義との整合性は `ViewerBridgeTests` /
/// `ViewerBridgeContractTests` がソースを読んで検証する。
///
/// 逆方向(JS → Swift の `findOptionsChanged`)は `ViewerBridgeMessage` が持つ。
public enum ViewerFindBridge {
    /// 検索バーを開く(未オープンなら表示してフォーカス)スクリプト。
    public static let openFindScript = ViewerBridge.PlainFunction.openFind.callScript

    /// 次のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findNextScript = ViewerBridge.PlainFunction.findNextIfOpen.callScript

    /// 前のマッチへ移動するスクリプト。検索バーが閉じている間は JS 側で無視される。
    public static let findPrevScript = ViewerBridge.PlainFunction.findPrevIfOpen.callScript

    /// 検索の3トグルの状態。
    public struct FindOptions: Equatable, Encodable {
        public var caseSensitive: Bool
        public var wholeWord: Bool
        public var useRegex: Bool

        public init(caseSensitive: Bool, wholeWord: Bool, useRegex: Bool) {
            self.caseSensitive = caseSensitive
            self.wholeWord = wholeWord
            self.useRegex = useRegex
        }
    }

    /// ロード時に検索トグルの保存済み状態を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdInitialFindOptions を読んで適用する。
    public static func initialFindOptionsScript(_ options: FindOptions) -> String {
        ViewerBridge.assignGlobalScript("window._mmdInitialFindOptions", options)
    }

    /// ロード時に検索バーのローカライズ済み文字列を注入するスクリプト。
    /// viewer.html 側は _mmdInitFind() が window._mmdFindStrings を読んで各要素に適用する。
    /// JSONEncoder でエスケープし、ローカライズ済み文字列に引用符等が含まれても
    /// JS オブジェクトリテラルを壊さないようにする。
    public static func findStringsScript(bundle: Bundle = .befoldKitResources) -> String {
        let strings: [String: String] = [
            "placeholder": String(localized: "viewer.find.placeholder", bundle: bundle),
            "previous": String(localized: "viewer.find.previous", bundle: bundle),
            "next": String(localized: "viewer.find.next", bundle: bundle),
            "matchCase": String(localized: "viewer.find.matchCase", bundle: bundle),
            "matchWholeWord": String(localized: "viewer.find.matchWholeWord", bundle: bundle),
            "useRegularExpression": String(localized: "viewer.find.useRegularExpression", bundle: bundle),
            "close": String(localized: "viewer.find.close", bundle: bundle),
            "withinDisplayedRange": String(localized: "viewer.find.withinDisplayedRange", bundle: bundle),
        ]
        return ViewerBridge.assignGlobalScript("window._mmdFindStrings", strings)
    }
}
