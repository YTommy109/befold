/// ブックマークのキー等価を決める単一の窓口。
///
/// ブラウザ習慣では ⌘D がブックマークだが、このアプリでは差分表示のほうが高頻度なので
/// 差分へ譲り、ブックマークを ⌘B へ移した。ただし差分項目は
/// `FeatureGate.isSourceDiffEnabled` の内側にしか無いため、無条件に ⌘B へ移すと
/// stable ビルドでは ⌘D が誰にも割り当たらないままブックマークだけが黙って移動する。
///
/// メニュー登録（`MainMenuBuilder`）とヘルプの説明文（`FeatureOverviewView`）が
/// 同じ値を読むことで、両者のずれを構造的に防ぐ。
enum BookmarkShortcut {
    /// ブックマーク項目のキー等価。差分表示を露出しているビルドでだけ ⌘B へ譲る。
    static var keyEquivalent: String {
        keyEquivalent(isSourceDiffEnabled: FeatureGate.isSourceDiffEnabled)
    }

    /// ヘルプ等に表示する表記（`⌘B` / `⌘D`）。
    static var displayName: String {
        displayName(isSourceDiffEnabled: FeatureGate.isSourceDiffEnabled)
    }

    /// テスト可能な純粋判定。実ビルドではゲートが片側に固定されるため、
    /// 両分岐はここで検証する（ゲート越しの検証は動いているビルドの側しか通らない）。
    static func keyEquivalent(isSourceDiffEnabled: Bool) -> String {
        isSourceDiffEnabled ? "b" : "d"
    }

    static func displayName(isSourceDiffEnabled: Bool) -> String {
        "⌘" + keyEquivalent(isSourceDiffEnabled: isSourceDiffEnabled).uppercased()
    }
}
