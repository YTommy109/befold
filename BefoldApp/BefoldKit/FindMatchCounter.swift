/// 検索の「現在位置 / 総ヒット数」表示を組み立てる。**書式はここだけが持つ。**
///
/// web の面は JS 側（`viewer-src/navigation.ts` の `formatNavigationCount`）が同じ
/// 書式を作る。PDF の面には JS が居ないので Swift 側にも同じものが要るが、
/// **両者は共有できない**（片方は TypeScript、片方は Swift）。分岐すると、同じバーの
/// はずが面によって違う見え方になる——「3/12」と「3 / 12」のような差は、実装した
/// 本人以外には仕様に見える。
///
/// そのため書式を固定するテスト（`FindMatchCounterTests`）を置いてある。
/// **`navigation.ts` 側を変えるときは、こちらとテストも一緒に変えること。**
///
/// 規則:
/// - ヒット 0 件は `"0/0"`。専用の文言を出すとバー幅が伸縮するため、件数表示のまま固定する
/// - 現在位置は 1 始まり（内部の index は 0 始まり）
/// - 未選択（index が負）でも 0 件でなければ 1 件目を指すものとして扱わない——`"0/N"` を返す
public enum FindMatchCounter {
    /// - Parameters:
    ///   - currentIndex: 0 始まりの現在位置。未選択なら負の値。
    ///   - count: 総ヒット数。
    public static func text(currentIndex: Int, count: Int) -> String {
        guard count > 0 else { return "0/0" }
        let current = currentIndex < 0 ? 0 : currentIndex + 1
        return "\(current)/\(count)"
    }
}
