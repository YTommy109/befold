import BefoldCLI

/// 開発中でまだ stable リリースに載せたくない機能の露出を一元管理する窓口。
/// dev リリース（バージョンがプレリリース）または DEBUG ビルドでのみ true。
/// stable 昇格時は該当機能の分岐を撤去してデフォルト有効化すること（撤去タスクを backlog 登録）。
///
/// 現在ゲートしている機能は**サイドバーの git ステータス系だけ**で、
/// 参照はすべて `isSidebarGitStatusEnabled` を経由する。露出点は次のとおりで、
/// TASK-187（stable 昇格）ではこれらの分岐を撤去する。
///
/// - `ViewerWindowController.makeSidebarGitStatusLoader(_:)`
///   — 状態取得そのもの。無効時は空を返すため、バッジ（ファイル行・フォルダー行）も
///     `.git/index` の監視も止まる。
/// - `ViewerWindowController.makeChangedFilesOnlyToggle()`
///   — サイドバーヘッダーの「変更されたファイルのみ表示」ボタン。無効時は nil で非表示。
/// - `MainMenuBuilder.makeViewMenuItem()`
///   — View メニューの「変更されたファイルのみ表示」項目。
/// - `SidebarDisplayPreference.init(defaults:isChangedFilesOnlyAvailable:)`
///   — 保存値の読み出し。無効時は保存値 ON でも OFF として読む。
///
/// この列挙は `FeatureGateEnumerationTests` がソース走査と突き合わせており、
/// 参照を足して列挙を更新し忘れるとテストが落ちる。
///
/// ゲート対象は git *ステータス*であって git 実行全般ではない。基準ディレクトリ表示
/// （`git rev-parse`）・Quick Open（`git ls-files`）・最近使ったリポジトリ・
/// `WorktreeCatalog`（`git worktree list`）は公開済み機能であり、stable でも常時動く。
enum FeatureGate {
    /// 実行中ビルドで開発中機能を露出してよいか。
    static var inProgressFeaturesEnabled: Bool {
        #if DEBUG
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: true)
        #else
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: false)
        #endif
    }

    /// サイドバーの git ステータス系（バッジ・変更ファイル絞り込み）を露出してよいか。
    /// 呼び出し側はこの名前付きプロパティだけを参照する（露出点は型の doc コメントを参照）。
    static var isSidebarGitStatusEnabled: Bool {
        inProgressFeaturesEnabled
    }

    /// テスト可能な純粋判定。
    static func inProgressFeaturesEnabled(version: String, isDebugBuild: Bool) -> Bool {
        isDebugBuild || AppVersion.isPrerelease(version)
    }
}
