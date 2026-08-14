import BefoldKit
import Foundation

/// 相対パスコピー・Quick Open のヘッダーが使う「基準ディレクトリ」を解決する型
/// (TASK-442.4)。
///
/// **この型は `fileListModel.baseDirectory` だけを書く。** 行は
/// `SidebarTreePresenter` が、選択・カレントディレクトリは `SidebarNavigator` が、
/// git 状態は `SidebarGitStatusCoordinator` が書く。同じ `FileListModel` を 4 つの型が
/// 書くが、属性が重ならないことが唯一の正当化根拠なので、この分割表を崩さないこと。
///
/// `SidebarGitStatusCoordinator` と**同居させない**。どちらも git を触るが、書き込み先も
/// 更新契機も別で(こちらは init とフォルダ移動、あちらは index 監視・トグル・一覧取得)、
/// 同居させると 1 つの型が世代カウンタ 2 本・pending タスク 2 本を抱えることになる
/// (docs/dev/rules/product-code.md の責務分離節)。
@MainActor
final class SidebarBaseDirectoryResolver {
    /// 解決結果の書き込み先。`baseDirectory` 以外は書かない。
    private let fileListModel: FileListModel
    /// git の読み取り。使うのは `repositoryRootLookup(forDirectoryAt:)` だけ。
    /// 未命中時に `git rev-parse` の subprocess を待つため async で、
    /// メインスレッド(SwiftUI の body 評価)では解決しない。
    private let git: any SidebarGitReading
    /// 解決タスクの世代番号。一覧取得・git 状態取得とは完了タイミングが独立するため、
    /// それぞれ別の世代で古い結果を捨てる。
    ///
    /// この世代は**この型の内側だけで完結する**(遅れて着地した解決結果を捨てるためだけに
    /// 使う)。git 側の sequence が FileListModel の recency 判定へ渡るのとは性質が違うので、
    /// 共通の世代型へ括っていない。
    private var generation = 0
    /// 直近に発行した解決タスク。テストから完了を待つために公開する。
    private(set) var pendingTask: Task<Void, Never>?
    /// 解決が反映されたことの通知先。差分表示モードの選択可否が基準ディレクトリの種別
    /// (git ルートか / 扱えないリポジトリか)から導かれるため、解決の着地を
    /// git 状態の反映と同じ口(`SidebarNavigatorHost.gitContextDidChange`)へ流す
    /// (TASK-438.2)。**この型が書くのは変わらず `baseDirectory` だけ**で、
    /// 通知はその書き込みの後段。循環参照を避けるため weak(git 状態側と同じ形)。
    private weak var host: SidebarNavigatorHost?

    init(fileListModel: FileListModel, git: any SidebarGitReading) {
        self.fileListModel = fileListModel
        self.git = git
    }

    /// 通知先を接続する。`SidebarNavigator.attach(to:)` が中継する
    /// (host は ViewerWindowController の super.init 後にしか渡せない)。
    func attach(to host: SidebarNavigatorHost) {
        self.host = host
    }

    /// 基準ディレクトリを取り直して fileListModel へ反映する。
    /// git ルートの解決はメイン外で行い、完了後にメインアクターへ戻して書き込む。
    /// ディレクトリが変わる契機(初期化・一覧更新・フォルダ移動)ごとに呼ぶ。
    func refresh() {
        let directory = fileListModel.currentDirectory
        let workspaceRoot = fileListModel.rootDirectory
        generation += 1
        let generation = generation
        pendingTask = Task {
            let lookup = await self.git.repositoryRootLookup(forDirectoryAt: directory)
            guard generation == self.generation else { return }
            self.fileListModel.baseDirectory = BaseDirectoryDescriptor(
                rootLookup: lookup,
                workspaceRoot: workspaceRoot
            )
            self.host?.gitContextDidChange()
        }
    }

    /// 進行中の解決を破棄する。ウィンドウを閉じるときに呼ぶ。
    /// 世代を進めるのは、走り出した subprocess が完了して結果を返しうるため
    /// (キャンセルは協調的 / TASK-300 と同型)。
    func cancelPending() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
    }
}
