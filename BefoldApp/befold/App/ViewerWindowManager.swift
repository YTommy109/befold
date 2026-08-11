import AppKit
import BefoldCLI
import BefoldKit
import SwiftUI

/// ビューアウィンドウの生成・管理(正規化パス → コントローラ辞書)と、
/// ウィンドウイベント(クローズ・rename・キー化)に伴うセッション記録の更新を担う。
///
/// このファイルは共有依存を受け取る composition root と、コントローラ辞書そのものの
/// 出し入れ(`register` / `detach`)だけを持つ。個々の責務は責務名を冠した extension
/// (`ViewerWindowManager+*.swift`)へ分かれている。
///
/// - `+OpenViewer`: ウィンドウを開く経路(新規生成・既存の前面化)
/// - `+GlobalDisplay`: アプリ全体の表示設定を全ウィンドウへ配る一括反映
/// - `+TabGroups`: タブ結合とタブ構成スナップショット、Space からはぐれた窓の救出
/// - `+RecentRepositories`: 「最近使ったリポジトリ」の記録
/// - `+SessionSync`: 辞書のキー付け替えとセッション記録、`ViewerWindowControllerDelegate` 準拠
///
/// extension から参照するため、stored property の多くは private ではなく internal に
/// している。いずれも「この型と その extension だけが読む」ことを前提にした実装詳細で、
/// 型の外から触ってよい API ではない。
@MainActor
final class ViewerWindowManager {
    /// 正規化パス → そのファイルを表示中のコントローラ群。
    /// 操作中(アクティブ)のウィンドウのサイドバー切替を最優先するため、同一ファイルを
    /// 複数ウィンドウで開くことを許す(1 対 1 ではない)。Finder/CLI からの再オープンは
    /// 依然として既存ウィンドウを前面化して重複を作らないが、ウィンドウ内のファイル切替では
    /// 他ウィンドウの有無に関わらず自ウィンドウを切り替える。
    private(set) var controllers: [String: [ViewerWindowController]] = [:]

    /// 開いている全コントローラ(同一ファイルの重複ウィンドウも含む)。
    /// 全ウィンドウへの一括反映(サイドバー・ツールバー再同期など)はこれを走査する。
    var allControllers: [ViewerWindowController] {
        controllers.values.flatMap(\.self)
    }

    let sessionStore: SessionStore
    let recentDocumentsStore: RecentDocumentsStore
    let sidebarDisplayPreference: SidebarDisplayPreference
    /// 全ウィンドウで共有する差分表示設定。ここで 1 つ持って openViewer で渡すことが、
    /// 「粒度はアプリ全体」(DiffDisplayPreference の doc コメント)を成立させている。
    let diffDisplayPreference: DiffDisplayPreference
    /// 全ウィンドウで共有する差分の取得元。ここで 1 つ持つことが、GitDiffLoader の
    /// 「同じ要求が重なったら git を二重起動しない」を窓をまたいで成立させている。
    /// 窓ごとに持つと、同じファイルを 2 窓で開いた状態の 1 回の保存で
    /// `git diff` が窓の数だけ起動する(TASK-325)。
    /// 機能ゲートが無効なビルドでは nil で、git diff を一切実行しない。
    let diffLoader: GitDiffLoader?
    let findOptionsPreference: FindOptionsPreference
    let codeFontPreference: CodeFontPreference
    let perFileState: PerFileStateStore
    let bookmarkStore: BookmarkStore
    /// openViewer のファイル存在ガードが使う I/O 抽象。静的な DefaultFileReader を直接叩かず
    /// ここへ集約することで、テストが InMemoryFileReader を注入して存在確認をモック化できる。
    let fileReader: any FileReading
    /// openViewer が生成するコントローラへ渡す ViewerStore の差し替え口。nil なら
    /// ViewerWindowController が従来どおり自前で生成する(本番の既定)。
    let makeStore: ((URL) -> ViewerStore)?
    /// openViewer が生成するコントローラへ渡すコンテンツペインの差し替え口。nil なら
    /// ViewerWindowController が従来どおり実 ViewerContentView(実 WKWebView)を生成する(本番の既定)。
    let makeContentView: (() -> AnyView)?
    /// 生成する全ウィンドウで共有する git 追跡ファイルの索引。同じリポジトリのファイルを
    /// 全ウィンドウ・Quick Open で共有する追跡ファイル索引。複数ウィンドウで開いても
    /// `git ls-files` は 1 回で済み、照合索引の実体も 1 つで済む(モノレポでは
    /// ウィンドウごとの複製が無視できない大きさになる)。ウィンドウが温めた同じ
    /// インスタンスを Quick Open の候補源もそのまま使う。
    let gitFileIndex: any GitFileIndexing
    /// サイドバーの git 状態バッジの取得元。全ウィンドウで 1 個を共有し、同じリポジトリを
    /// 開いた複数ウィンドウで `git status` の実行とキャッシュをまとめる。
    /// 既定は無効化状態(常に空)で、本番のルート解決付きインスタンスは AppDelegate が差し込む。
    var gitStatusStore = GitStatusStore()
    /// 「最近使ったリポジトリ」の記録先。git ルートを持つファイルを開いた際に record、
    /// そのウィンドウが閉じるたび・アプリ終了時に updateLastTabGroup でタブ構成を更新する。
    let recentRepositoriesStore: RecentRepositoriesStore
    /// root からメニュー表示用ラベルと本体リポジトリのルートを解決する。既定は実 GitRepository。
    /// 解決は MainActor の外(detached タスク)で走るため @Sendable が要る。
    /// テストは実 git を起動しないフェイクへ差し替える。
    let repositoryIdentityResolver: @Sendable (URL) -> RepositoryIdentity
    /// 「最近使ったリポジトリ」へ新しい本体ルートを記録した直後に呼ばれる。
    /// AppDelegate が WorktreeCatalog を追随させるために使う。
    let onRepositoryRecorded: (URL) -> Void

    /// - Parameter sidebarDisplayPreference: 本番では必ず AppDelegate が持つ単一の共有インスタンスを渡すこと。
    ///   デフォルト値は、不可視ファイル挙動に無関心なテストが省略できるようにするためのもの。
    /// - Parameter diffDisplayPreference: 差分レイアウトは全ウィンドウで同じ答えになる必要があるため、
    ///   ここで受けた 1 つを openViewer が全コントローラへ渡す。既定値を持たせないのは、
    ///   渡し忘れが静かに別インスタンスになるのを防ぐため（TASK-319）。
    /// - Parameter findOptionsPreference: 同上。検索トグル挙動に無関心なテストが省略できるようにする。
    /// - Parameter perFileState: 同上。ファイル毎の永続表示状態(倍率・表示モード・
    ///   スクロール位置)の束。これらの挙動に無関心なテストが省略できるようにする。
    /// - Parameter bookmarkStore: 同上。ブックマーク挙動に無関心なテストが省略できるようにする。
    /// - Parameter makeStore: 生成するコントローラの ViewerStore を差し替える。既定の nil では
    ///   コントローラが自前で生成するため本番挙動は変わらない。テストが実 FileWatcher と
    ///   実ファイル読込を避けて生成パイプラインごと unit 化するための唯一のシーム。
    /// - Parameter makeContentView: テスト専用シーム。生成するコントローラのコンテンツペイン
    ///   (実 WKWebView)を差し替える。既定の nil は本番経路(実 WKWebView を生成する)。
    /// - Parameter gitFileIndex: 生成する全ウィンドウで共有する git 追跡ファイルの索引。
    ///   既定は実 `git` を実行する実装。テストは実 subprocess を避けるため差し替えられる。
    init(
        sessionStore: SessionStore, recentDocumentsStore: RecentDocumentsStore,
        sidebarDisplayPreference: SidebarDisplayPreference = SidebarDisplayPreference(),
        diffDisplayPreference: DiffDisplayPreference,
        diffLoader: GitDiffLoader? = ViewerWindowManager.makeDiffLoader(),
        findOptionsPreference: FindOptionsPreference = FindOptionsPreference(),
        codeFontPreference: CodeFontPreference = CodeFontPreference(),
        perFileState: PerFileStateStore = PerFileStateStore(),
        bookmarkStore: BookmarkStore,
        fileReader: any FileReading = DefaultFileReader(),
        makeStore: ((URL) -> ViewerStore)? = nil,
        makeContentView: (() -> AnyView)? = nil,
        gitFileIndex: any GitFileIndexing = GitCommandFileIndex(),
        recentRepositoriesStore: RecentRepositoriesStore = RecentRepositoriesStore(),
        repositoryIdentityResolver: @escaping @Sendable (URL) -> RepositoryIdentity = {
            GitRepository().repositoryIdentity(forRoot: $0)
        },
        onRepositoryRecorded: @escaping (URL) -> Void = { _ in }
    ) {
        self.gitFileIndex = gitFileIndex
        self.sessionStore = sessionStore
        self.recentDocumentsStore = recentDocumentsStore
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.diffDisplayPreference = diffDisplayPreference
        self.diffLoader = diffLoader
        self.findOptionsPreference = findOptionsPreference
        self.codeFontPreference = codeFontPreference
        self.perFileState = perFileState
        self.bookmarkStore = bookmarkStore
        self.fileReader = fileReader
        self.makeStore = makeStore
        self.makeContentView = makeContentView
        self.recentRepositoriesStore = recentRepositoriesStore
        self.repositoryIdentityResolver = repositoryIdentityResolver
        self.onRepositoryRecorded = onRepositoryRecorded
    }

    /// 差分の取得元を 1 つ作る。機能ゲートが無効なら nil で、git diff を一切実行しない。
    /// 生成をここへ限ることで、ウィンドウ側が自前で作る経路を無くしている。
    static func makeDiffLoader() -> GitDiffLoader? {
        FeatureGate.isSourceDiffEnabled ? GitDiffLoader() : nil
    }

    /// controller を key のコントローラ群へ登録する。
    /// 辞書 `controllers` の書き換えはこのファイルの register / detach だけに閉じている
    /// (`private(set)` のまま extension から直接触らせないための入口)。
    func register(_ controller: ViewerWindowController, forKey key: String) {
        controllers[key, default: []].append(controller)
    }

    /// controller を key のコントローラ群から取り除き、空になったキーは辞書から消す。
    func detach(_ controller: ViewerWindowController, fromKey key: String) {
        guard var list = controllers[key] else { return }
        list.removeAll { $0 === controller }
        controllers[key] = list.isEmpty ? nil : list
    }
}
