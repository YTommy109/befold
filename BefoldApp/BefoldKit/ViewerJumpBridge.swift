import Foundation

/// 文書内ジャンプバー(Swift → JS)のブリッジ契約を集約する。
///
/// `ViewerBridge` の extension ではなく**兄弟の型**にしてある。extension はファイルを
/// 分けても型グループの行数には合算されるため、責務を分けたことにならない
/// (`ViewerCsvBridge` と同じ方針)。JS 側の定義との整合性は `ViewerBridgeTests` /
/// `ViewerBridgeContractTests` がソースを読んで検証する。
///
/// 逆方向(JS → Swift の `jumpLevelsChanged`)は `ViewerBridgeMessage` が持つ。
public enum ViewerJumpBridge {
    /// 文書内ジャンプバーを開くスクリプト。目印の種類(kind)を引数に取るため
    /// `ViewerBridge.PlainFunction`(引数なしの `name()` 形式)には載せられない。
    /// JS 側の定義は `ViewerBridgeTests` が存在を検証する。
    /// kind は JSON エンコードを経由させる(他の注入経路と同じエスケープの単一経路)。
    public static func openJumpScript(kind: String) -> String {
        guard let literal = ViewerBridge.jsonLiteral(kind) else {
            return "_mmdOpenJump(null)"
        }
        return "_mmdOpenJump(\(literal))"
    }

    /// いま使える目印の種類を JS へ知らせるスクリプト(TASK-485.18)。
    /// JS 側は開いているジャンプバーの種類がこの一覧から外れていれば閉じる。
    /// 開くときの guard(`DocumentCommandController.openJump`)と同じ
    /// `ViewerCapabilities.canJump(to:)` の結果が渡るため、可否の規則は Swift 側の
    /// 1 箇所だけが持つ(JS 側で判定し直さない)。
    /// エンコードに失敗したときは空配列を入れる。ここでの空は「どの種類も使えない」で、
    /// バーを閉じる方向へ倒れる — 使えない種類のバーが残るより安全な縮退。
    public static func jumpAvailabilityScript(kinds: [String]) -> String {
        "_mmdApplyJumpAvailability(\(ViewerBridge.jsonLiteral(kinds) ?? "[]"))"
    }

    /// ロード時に保存済みの見出しレベルを注入するスクリプト。
    /// viewer.html 側は _mmdInitHeadingLevels() が window._mmdInitialJumpLevels を読んで適用する。
    /// **空配列（3 つとも OFF）と非配列は別の意味**で、JS は配列ならそのままユーザー状態として
    /// 尊重し、非配列（未注入・null）のときだけ既定の 3 レベルへ落ちる。
    /// このスクリプトは常に注入する。呼び出し側が値を持たない場合（QuickLook など）は
    /// `HeadingJumpLevels.default` を渡す（JS 側の既定と同じ意味になる）。
    /// エンコードに失敗したときは `null` を入れて既定へ落とす（`[]` だと
    /// 「ユーザーが 3 つとも OFF にした」の意味になり、目印が 0 件へ縮退する）。
    public static func initialJumpLevelsScript(_ levels: HeadingJumpLevels) -> String {
        ViewerBridge.assignGlobalScript(
            "window._mmdInitialJumpLevels", levels.storedValue, fallback: ViewerBridge.defaultingFallback
        )
    }

    /// ロード時に文書内ジャンプバーのローカライズ済み文字列を注入するスクリプト。
    /// viewer.html 側は _mmdInitJump() が window._mmdJumpStrings を読んで各要素に適用する。
    public static func jumpStringsScript(bundle: Bundle = .befoldKitResources) -> String {
        let strings: [String: String] = [
            "previous": String(localized: "viewer.jump.previous", bundle: bundle),
            "next": String(localized: "viewer.jump.next", bundle: bundle),
            "close": String(localized: "viewer.jump.close", bundle: bundle),
            "withinDisplayedRange": String(localized: "viewer.jump.withinDisplayedRange", bundle: bundle),
            "headingLevel": String(localized: "viewer.jump.headingLevel", bundle: bundle),
        ]
        return ViewerBridge.assignGlobalScript("window._mmdJumpStrings", strings)
    }
}
