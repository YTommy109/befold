import BefoldKit
import Foundation

/// サイドバーが必要とする git の読み取り(TASK-442.6)。
///
/// `SidebarNavigator` に git 型を直接持ち込まないための境界。以前はこれを
/// `resolveGitRoot` / `loadGitStatuses` の 2 本のクロージャで表していたが、
/// **2 本まとめて 1 つの依存**にしたほうが注入点が減り、テスト側も既定実装を
/// 型で与えられる。
///
/// **`makeGitIndexWatcher` はここに入れない。** 既定が `FileWatcher` であり、
/// git ではなくファイル監視だから(名前が実態と合わなくなる)。
///
/// 2 つのメソッドの利用者は別々で、片方だけを使う。
/// - `repositoryRoot` … `SidebarBaseDirectoryResolver`(相対パスコピー・Quick Open の基準)
/// - `statuses` … `SidebarGitStatusCoordinator`(バッジ・変更ファイル絞り込み)
///
/// **フィーチャーゲートの効き方が 2 つで違う**ことに注意する。git 状態の取得は
/// サイドバー git 状態のゲートで止まるが、リポジトリルートの解決は止まらない
/// (基準ディレクトリの表示はゲート対象外)。ゲートの判定は composition root
/// (`ViewerWindowAssembler`)が行い、ここには持ち込まない——だからこの型は
/// ゲート値ではなく「状態取得の相手が居るかどうか」(`statusStore` の有無)だけを見る。
@MainActor
protocol SidebarGitReading {
    /// ディレクトリが属する git 作業ツリーのルート。git 管理外なら nil。
    func repositoryRoot(forDirectoryAt url: URL) async -> URL?
    /// ディレクトリ内のファイルの git 状態。
    func statuses(forDirectoryAt url: URL, policy: GitStatusRefreshPolicy) async -> GitStatusResult
}

/// git を一切見ない既定実装。`SidebarNavigator.init` の既定値。
///
/// 「常に空を返すクロージャ」を各テストが個別に書いていたのを型 1 つへ寄せたもの。
/// 空の `GitStatusResult` は「変更が無い」ではなく「機能が無効」を表すが、
/// 受け手(`FileListModel.applyGitStatus`)にとってはどちらも同じ扱いでよい。
struct DisabledSidebarGitReading: SidebarGitReading {
    func repositoryRoot(forDirectoryAt _: URL) async -> URL? {
        nil
    }

    func statuses(forDirectoryAt _: URL, policy _: GitStatusRefreshPolicy) async -> GitStatusResult {
        .empty
    }
}

/// 実際の git を読む実装。
///
/// `statusStore` が nil なら状態取得だけが無効(空を返す)で、ルート解決は動く。
/// この非対称は上のプロトコル doc に書いたゲートの効き方をそのまま表している。
struct SidebarGitReader: SidebarGitReading {
    private let fileIndex: any GitFileIndexing
    private let statusStore: GitStatusStore?

    init(fileIndex: any GitFileIndexing, statusStore: GitStatusStore?) {
        self.fileIndex = fileIndex
        self.statusStore = statusStore
    }

    /// 未命中時は `git rev-parse` の subprocess を同期で待つため、メインアクターを
    /// 離して解決する(サイドバーのヘッダー表示のためだけにフォルダ移動のたび
    /// メインスレッドを止めないため)。
    func repositoryRoot(forDirectoryAt url: URL) async -> URL? {
        let fileIndex = fileIndex
        return await Task.detached { fileIndex.repositoryRoot(forDirectoryAt: url) }.value
    }

    func statuses(forDirectoryAt url: URL, policy: GitStatusRefreshPolicy) async -> GitStatusResult {
        guard let statusStore else { return .empty }
        return await statusStore.statuses(forDirectoryAt: url, policy: policy)
    }
}
