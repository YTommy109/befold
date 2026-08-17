import BefoldCLI

/// 開発中でまだ stable リリースに載せたくない機能の露出を一元管理する窓口。
/// dev リリース（バージョンがプレリリース）または DEBUG ビルドでのみ true。
///
/// dev ビルドで開くことは配布経路の側で担保されている。`release.yml` の
/// `.app をビルド・署名する` ステップが `MARKETING_VERSION="${GITHUB_REF_NAME#v}"` を
/// 注入するため、`v1.15.0-dev.1` タグのビルドは `1.15.0-dev.1` を名乗り
/// `AppVersion.isPrerelease` が true になる。stable タグ（`v1.15.0`）では false。
///
/// stable 昇格時は該当機能の分岐を撤去してデフォルト有効化すること（撤去タスクを backlog 登録）。
/// 呼び出し側は `inProgressFeaturesEnabled` を直接見ず、機能ごとの名前付きプロパティを経由する。
///
/// ## 文書内ジャンプ（`isDocumentJumpEnabled`）
/// 見出し・差分の変更ブロック・関数定義を検索窓と同じ UI で前後移動する機能（TASK-485）。
/// 安定稼働を確認するまで stable には載せない。露出点はメニュー項目とコマンドの可否判定で、
/// Swift 側で塞ぐため viewer 側（`window._mmdHostFeatures`）へは伸ばしていない。
enum FeatureGate {
    /// 実行中ビルドで開発中機能を露出してよいか。
    static var inProgressFeaturesEnabled: Bool {
        #if DEBUG
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: true)
        #else
            inProgressFeaturesEnabled(version: AppVersion.current, isDebugBuild: false)
        #endif
    }

    /// 文書内ジャンプ（TASK-485）を露出してよいか。
    /// 呼び出し側はこの名前付きプロパティだけを参照する（露出点は型の doc コメントを参照）。
    static var isDocumentJumpEnabled: Bool {
        inProgressFeaturesEnabled
    }

    /// テスト可能な純粋判定。
    static func inProgressFeaturesEnabled(version: String, isDebugBuild: Bool) -> Bool {
        isDebugBuild || AppVersion.isPrerelease(version)
    }
}
