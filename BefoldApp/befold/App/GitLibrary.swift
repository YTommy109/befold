import CGitShim
import Foundation
import libgit2

/// libgit2 を使うための唯一の入口。
///
/// ## リポジトリを開くのはこの型だけ
///
/// `git_repository_open` / `git_repository_open_ext` の直接呼び出しは、swiftlint の
/// custom rule `git_repository_open_outside_git_library` がこのファイル以外で error にする。
/// 開けなかったときの写像(下記)を 1 箇所に保つためで、doc コメントだけでは守られない。
/// libgit2 の他の API(status / diff / worktree など)は各実装が直接呼んでよい。
///
/// ## 初期化を `AppDelegate` から呼ばない理由
///
/// libgit2 はすべての API 呼び出しの前に `git_libgit2_init` を必要とし、config の検索パス
/// 無効化はリポジトリを開くより前でなければ効かない。この順序を `AppDelegate` の起動処理で
/// 担保すると、`AppDelegate` を通らない経路(ユニットテスト、将来の appex や CLI)で
/// 配線漏れが静かに成立する。`static let` の一度きり初期化に載せ、リポジトリを開く唯一の
/// 関数がそれに触る形にすれば、初期化されないまま開くコードが書けなくなる。
///
/// `git_libgit2_shutdown` は呼ばない。init/shutdown は参照カウント方式で、ここでの初期化は
/// プロセスの寿命と一致するため、終了時に解放しても得るものが無い(むしろ、まだ生きている
/// `git_repository` があれば解放後に触ることになる)。
enum GitLibrary {
    /// リポジトリを開けなかった理由。
    ///
    /// 呼び出し側の「確定した答えはキャッシュしてよいが、不明は覚えてはならない」という
    /// 既存の規約(`GitRootLookup` の `.notARepository` / `.undetermined`)へそのまま対応する。
    enum OpenFailure: Error, Sendable, Equatable {
        /// git 管理下ではないことが確定した。キャッシュしてよい。
        case notARepository
        /// リポジトリらしきものはあるが libgit2 では扱えない。キャッシュしてはならない。
        ///
        /// partial clone、reftable 形式、未知の `extensions.*` がここに入る
        /// (libgit2 1.9.2 ではいずれも「未対応の拡張」として同じ形で失敗する)。
        case unusable
    }

    /// 無効化する config レベル。マシン全体の設定(`/etc/gitconfig`)と XDG 配下の設定を
    /// 読まないようにして、環境ごとの差で挙動が変わらないようにする。
    ///
    /// 目的は決定性であって、任意コマンド実行の遮断ではない。外部 git プロセス方式では
    /// `core.fsmonitor` / `core.hooksPath` が任意コマンドの起動経路になるため遮断が必須だったが、
    /// libgit2 はフックも textconv も外部 diff driver も実行しない。
    ///
    /// **`GIT_CONFIG_LEVEL_GLOBAL`(`~/.gitconfig`)は意図して無効化しない。**
    /// 無効化すると `core.excludesFile` によるグローバルな ignore 設定が効かなくなり、
    /// ユーザーが除外したつもりのファイルがサイドバーに untracked として現れる。
    /// 撤去した外部 git プロセス方式でも `HOME` を意図的に引き継いで `~/.gitconfig` を
    /// 有効にしており、その挙動をここでも保つ。
    /// この判断は `GitLibraryTests.keepsGlobalConfigSearchPathEnabled` が守る。
    static let disabledConfigLevels: [git_config_level_t] = [
        GIT_CONFIG_LEVEL_SYSTEM,
        GIT_CONFIG_LEVEL_XDG,
    ]

    /// プロセスで一度だけ走る初期化。`static let` は swift_once で保護される。
    private static let bootstrap: Void = {
        git_libgit2_init()
        for level in disabledConfigLevels {
            _ = befold_git_opts_set_search_path(level.rawValue, "")
        }
    }()

    /// 初期化が済んでいることを保証する。テストから初期化後の状態を観測するために公開する。
    static func ensureInitialized() {
        _ = bootstrap
    }

    /// 指定したレベルの config 検索パス。無効化されていれば空文字を返す。
    static func configSearchPath(for level: git_config_level_t) -> String? {
        ensureInitialized()
        var buf = git_buf()
        defer { git_buf_dispose(&buf) }
        guard befold_git_opts_get_search_path(level.rawValue, &buf) == 0 else { return nil }
        guard let ptr = buf.ptr else { return "" }
        return String(cString: ptr)
    }

    /// リポジトリを開いて `body` を実行し、必ず解放する。
    ///
    /// `git_repository` はスレッド間で共有できないため、開いたポインタを保持して使い回さない。
    /// 呼び出しごとに開き直す(外部プロセスの起動より桁で安い)。
    ///
    /// - Parameter url: 作業ツリー内の任意のパス。親方向へ探索して作業ツリーを見つける
    ///   (`git rev-parse --show-toplevel` と同じ振る舞い)。
    static func withRepository<Value>(
        at url: URL,
        _ body: (OpaquePointer) -> Value
    ) -> Result<Value, OpenFailure> {
        ensureInitialized()
        var repository: OpaquePointer?
        let code = git_repository_open_ext(&repository, url.path, 0, nil)
        // 失敗の切り分けはエラーコードだけで行う。libgit2 のエラーメッセージ
        // (`unsupported extension name ...` など)は版で変わりうるため見ない。
        guard code == 0, let repository else {
            return .failure(code == GIT_ENOTFOUND.rawValue ? .notARepository : .unusable)
        }
        defer { git_repository_free(repository) }
        return .success(body(repository))
    }
}
