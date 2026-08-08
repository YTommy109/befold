/// ブックマークのキー等価を決める単一の窓口。
///
/// ブラウザ習慣どおり ⌘D。以前は差分表示が ⌘D を使っていたため dev ビルドだけ ⌘B へ
/// 逃がす分岐を持っていたが、差分は表示モードとして ⌘3 へ移ったので分岐は不要になった
/// （ビルド種別によってキーが変わらない = 説明文と実際の割り当てがずれようがない）。
///
/// メニュー登録（`MainMenuBuilder`）とヘルプの説明文（`FeatureOverviewView`）が
/// 同じ値を読むことで、両者のずれを構造的に防ぐ。
enum BookmarkShortcut {
    /// ブックマーク項目のキー等価。
    static let keyEquivalent = "d"

    /// ヘルプ等に表示する表記（`⌘D`）。
    static let displayName = "⌘" + keyEquivalent.uppercased()
}
