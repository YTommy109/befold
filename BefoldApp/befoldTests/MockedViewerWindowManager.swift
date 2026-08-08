import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation

/// 実 `git` を起動せず、温め要求だけを記録する索引。
/// unit テストの既定として使い、ウィンドウ生成で subprocess が走らないようにする。
final nonisolated class RecordingGitFileIndex: GitFileIndexing, @unchecked Sendable {
    private let lock = NSLock()
    private var _warmedPaths: [URL] = []
    /// 解決させたいリポジトリルート。既定の nil は「git 管理外」で、実 `git` は起こさない。
    /// 差分取得のようにルート解決が前提の経路をテストするときだけ渡す。
    private let repositoryRootOverride: URL?

    init(repositoryRoot: URL? = nil) {
        repositoryRootOverride = repositoryRoot
    }

    /// プロトコル要件はこちら(`forDirectoryAt:` は拡張の静的ディスパッチで、
    /// `any GitFileIndexing` 越しには上書きが効かない)。
    func repositoryRoot(forFileAt _: URL) -> URL? {
        repositoryRootOverride
    }

    var warmedPaths: [URL] {
        lock.lock(); defer { lock.unlock() }; return _warmedPaths
    }

    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }

    func warm(forFileAt url: URL) {
        lock.lock(); defer { lock.unlock() }
        _warmedPaths.append(url)
    }
}

/// ViewerWindowManager を実 FS へ触れさせずに組み立てるテスト用フィクスチャ。
///
/// openViewer が生成する ViewerWindowController は既定では実 FileWatcher・実ファイル読込・
/// 実ディレクトリ列挙を踏むため、そのままでは Integration にせざるを得なかった。
/// ViewerWindowManager の makeStore シーム(TASK-116.13)へ
/// InMemoryFileReader + MockFileWatcher + 空の列挙を渡すことで、生成パイプラインごと unit 化する。
///
/// サイドバーの entries を検証するテストには使えない(列挙は常に空)。
/// 実列挙そのものが対象のテストは Integration に残すこと。
@MainActor
struct MockedViewerWindowManager {
    let defaults: UserDefaults
    let fileReader: InMemoryFileReader
    let sessionStore: SessionStore
    let recentDocumentsStore: RecentDocumentsStore
    let perFileState: PerFileStateStore
    let sidebarDisplayPreference: SidebarDisplayPreference
    /// 生成される全ウィンドウが共有する差分表示設定。機能ゲートに依存しないよう
    /// isAvailable を明示して、dev/stable いずれのビルドでも同じ挙動でテストする。
    let diffDisplayPreference: DiffDisplayPreference
    /// 生成される全ウィンドウが共有する差分の取得元。既定は nil(差分を取りに行かない)で、
    /// 差分に無関心なテストが実 `git diff` を起こさないことを保証する。
    /// 差分を測るテストは init の diffReader へスタブを渡す。
    let diffLoader: GitDiffLoader?
    /// 本番 UserDefaults へ書かないよう、隔離 defaults で明示的に生成して注入する。
    let bookmarkStore: BookmarkStore
    /// 生成される全ウィンドウが共有する git 索引。実 `git` を起動しない記録用フェイク。
    let gitFileIndex: RecordingGitFileIndex
    let recentRepositoriesStore: RecentRepositoriesStore
    let manager: ViewerWindowManager

    /// - Parameters:
    ///   - files: 存在するものとして扱う URL。VWM の存在ガードと、
    ///     生成される ViewerStore の読込の双方が同じ InMemoryFileReader を共有する。
    ///   - directories: 存在するディレクトリとして扱う URL(例: フォルダーオープンのフォールバック検証)。
    ///   - diffReader: 渡すと、生成される全ウィンドウが共有する GitDiffLoader をこの取得器で作る。
    ///     既定の nil はローダー自体を持たない(差分を取りに行かない)。
    init(
        files: [URL], directories: [URL] = [], prefix: String = "ViewerWindowManagerTests",
        contents: String = "graph TD;", repositoryRoot: URL? = nil,
        diffReader: (any GitDiffReading)? = nil
    ) {
        let defaults = makeIsolatedDefaults(prefix: prefix)
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, contents) }),
            directories: Set(directories.map(\.path))
        )
        self.defaults = defaults
        self.fileReader = fileReader
        sessionStore = SessionStore(defaults: defaults)
        recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        perFileState = PerFileStateStore(defaults: defaults)
        sidebarDisplayPreference = SidebarDisplayPreference(defaults: defaults)
        let diffDisplayPreference = DiffDisplayPreference(defaults: defaults)
        self.diffDisplayPreference = diffDisplayPreference
        let diffLoader = diffReader.map { GitDiffLoader(reader: $0) }
        self.diffLoader = diffLoader
        let bookmarkStore = BookmarkStore(defaults: defaults)
        self.bookmarkStore = bookmarkStore
        let gitFileIndex = RecordingGitFileIndex(repositoryRoot: repositoryRoot)
        self.gitFileIndex = gitFileIndex
        let recentRepositoriesStore = RecentRepositoriesStore(defaults: defaults)
        self.recentRepositoriesStore = recentRepositoriesStore
        manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            sidebarDisplayPreference: sidebarDisplayPreference,
            diffDisplayPreference: diffDisplayPreference,
            diffLoader: diffLoader,
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            makeContentView: placeholderViewerContent,
            gitFileIndex: gitFileIndex,
            recentRepositoriesStore: recentRepositoriesStore
        )
    }

    /// テスト終了時にウィンドウを閉じる。openViewer した全テストで呼ぶこと。
    func closeAll() {
        manager.allControllers.forEach { $0.close() }
    }
}
