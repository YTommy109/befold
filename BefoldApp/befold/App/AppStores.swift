import BefoldKit
import Foundation

/// アプリ全体で 1 個ずつ持つ永続化ストアと表示設定の一式。
///
/// これらは**アプリ全体で共有されることが設計上の前提**で、機能ごとに生成し直すと
/// 片方のウィンドウでのトグルがもう片方へ伝わらない、CLI と GUI で書き込みが衝突する、
/// といった形で静かに壊れる(実例: `DiffDisplayPreference` が窓ごとに生成され 2 窓で
/// トグルが同期しなかった = TASK-319)。
///
/// 個別に引数で配ると渡し忘れがコンパイルエラーにならないため、**束ねた 1 個を配る**。
/// 受け取り側が同じ `AppStores` を持っている限り、共有は構造として保たれる。
@MainActor
struct AppStores {
    let sessionStore = SessionStore()
    let recentDocumentsStore = RecentDocumentsStore()
    let bookmarkStore = BookmarkStore(defaults: .standard)
    let recentRepositoriesStore = RecentRepositoriesStore()
    let displayDefaults = SidebarDisplayDefaults()
    let diffDisplayPreference = DiffDisplayPreference(defaults: .standard)
    let findOptionsPreference = FindOptionsPreference()
    let headingJumpLevelDefaults = HeadingJumpLevelDefaults()
    let codeFontPreference = CodeFontPreference()
    let csvNumberFormatPreference = CsvNumberFormatPreference()
    let perFileState = PerFileStateStore()
    /// 新しいウィンドウの出発点になる寸法。アプリ全体で 1 個(TASK-583)。
    let windowFrame = WindowFrameStore(defaults: .standard)
    /// 「最近使ったリポジトリ」メニューの階層化に使う worktree 一覧キャッシュ。
    /// git 呼び出しは起動時と新規リポジトリ記録時の非同期解決だけで、メニュー構築では読むだけ。
    let worktreeCatalog = WorktreeCatalog()

    init() {
        Self.removeRetiredDisplayStateKeys(from: .standard)
    }

    /// 永続化をやめた表示状態(スクロール位置・表示モード)が使っていたキーを既存ユーザーの
    /// defaults から消す。
    ///
    /// **移行はしない。** 移行先が無い(永続化そのものをやめた = TASK-565)。読み手が 0 に
    /// なったキーを残すと、次に同名のキーを再利用したとき誤って読まれる
    /// (CLAUDE.md「UserDefaults キーの廃止・改名」)。
    ///
    /// `ViewerSourceModes` / `SourceDiffEnabled` は、消えた `DisplayModeStore` の
    /// 一度きり移行が掃除していた旧キー。担い手が消えるのでここへ引き取る。
    ///
    /// `WindowFrames` はファイル単位のウィンドウ寸法(TASK-583 で廃止)。**移行しない**——
    /// 記録は実測 104 件あったが、そのどれを「アプリ全体で 1 個」の値に選ぶかに根拠が無い。
    static func removeRetiredDisplayStateKeys(from defaults: UserDefaults) {
        for key in retiredDisplayStateKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// テストが同じ一覧を参照できるよう内部可視性にしてある。
    static let retiredDisplayStateKeys = [
        "ViewerScrollPositions.rendered",
        "ViewerScrollPositions.source",
        "ViewerDisplayModes",
        "ViewerSourceModes",
        "SourceDiffEnabled",
        "WindowFrames",
    ]
}
