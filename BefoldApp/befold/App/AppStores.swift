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
    let codeFontPreference = CodeFontPreference()
    let perFileState = PerFileStateStore()
    /// 「最近使ったリポジトリ」メニューの階層化に使う worktree 一覧キャッシュ。
    /// git 呼び出しは起動時と新規リポジトリ記録時の非同期解決だけで、メニュー構築では読むだけ。
    let worktreeCatalog = WorktreeCatalog()

    init() {}
}
