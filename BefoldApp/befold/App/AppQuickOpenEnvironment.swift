import BefoldKit
import Foundation

/// `QuickOpenModel` を実際のアプリ状態(git 索引・履歴・ブックマーク・実 FS)へ繋ぐ実装。
///
/// 候補集合はパネルを開いた時点で 1 度だけ組み立てる。入力のたびに `git ls-files` や
/// ディレクトリ走査をやり直さないためで、絞り込みはメモリ上の候補に対して同期で行う。
@MainActor
final class AppQuickOpenEnvironment: QuickOpenEnvironment {
    private let gitIndex: any GitFileIndexing
    private let recentDocumentsStore: RecentDocumentsStore
    private let bookmarkStore: BookmarkStore
    private let sidebarDisplayPreference: SidebarDisplayPreference
    private let fileReader: any FileReading
    /// いま開いているファイル。ウィンドウが 1 枚も無ければ nil。
    private let currentFileURL: URL?

    init(
        gitIndex: any GitFileIndexing,
        recentDocumentsStore: RecentDocumentsStore,
        bookmarkStore: BookmarkStore,
        sidebarDisplayPreference: SidebarDisplayPreference,
        currentFileURL: URL?,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.gitIndex = gitIndex
        self.recentDocumentsStore = recentDocumentsStore
        self.bookmarkStore = bookmarkStore
        self.sidebarDisplayPreference = sidebarDisplayPreference
        self.currentFileURL = currentFileURL
        self.fileReader = fileReader
    }

    var baseDirectory: URL? {
        currentFileURL?.deletingLastPathComponent()
    }

    var includingHiddenFiles: Bool {
        sidebarDisplayPreference.showHiddenFiles
    }

    /// 候補集合の構築は `git rev-parse` / `git ls-files` のサブプロセス待ちと
    /// ディレクトリ再帰走査、候補ごとの `normalizedPathKey`(FS I/O)を伴うため、
    /// MainActor では走らせない(応答しないボリュームでは秒単位で止まる)。
    /// UserDefaults から取るだけの履歴・ブックマークと設定値は MainActor 上で捕捉し、
    /// Sendable な値だけを持って detached タスクへ渡す。
    func candidateSet() async -> QuickOpenCandidateSet {
        let recentURLs = recentDocumentsStore.recentURLs()
        let bookmarkedURLs = bookmarkStore.bookmarkedURLs()
        let includingHiddenFiles = includingHiddenFiles
        let gitIndex = gitIndex

        guard let currentFileURL else {
            // 開いているファイルが無ければ探す起点も無い。履歴とブックマークだけを出す。
            return await Task.detached(priority: .userInitiated) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                return QuickOpenCandidates.collect(
                    root: home,
                    anchorFile: home,
                    gitIndex: DisabledGitFileIndex(),
                    scanner: DirectoryFileScanner(maximumDepth: 0),
                    recentURLs: recentURLs,
                    bookmarkedURLs: bookmarkedURLs,
                    includingHiddenFiles: includingHiddenFiles
                )
            }.value
        }
        return await Task.detached(priority: .userInitiated) {
            // ルート解決は索引に一本化する。ここで別の GitRepository を new して rev-parse を
            // 重ねず、collect が引く追跡ファイル索引と同じ 1 回の解決結果を共有する。
            let root = gitIndex.repositoryRoot(forFileAt: currentFileURL)
                ?? currentFileURL.deletingLastPathComponent()
            return QuickOpenCandidates.collect(
                root: root,
                anchorFile: currentFileURL,
                gitIndex: gitIndex,
                scanner: DirectoryFileScanner(),
                recentURLs: recentURLs,
                bookmarkedURLs: bookmarkedURLs,
                includingHiddenFiles: includingHiddenFiles
            )
        }.value
    }

    func directoryEntries(in directory: URL) async -> [URL]? {
        // 列挙とソートは DirectoryLister の単一情報源へ委譲する。自前で
        // FileManager を叩くと返却順が未定義になり、候補順・選択位置・補完表記が
        // 非決定的になる。隠しファイルの出し分けは QuickOpenModel が入力に応じて
        // 決めるため、ここでは隠しファイルも含めた全件を名前昇順で返す。
        // キーストロークごとに走るため、列挙自体は MainActor の外で行う。
        // 列挙失敗(nil)はそのまま通す。ここで空へ畳むと「一致なし」と区別できなくなる。
        await Task.detached(priority: .userInitiated) {
            DirectoryLister.allEntriesSorted(in: directory)
        }.value
    }

    /// Enter/Tab はキー入力のたびに走るため、stat を MainActor の外へ逃がす。
    func isDirectory(_ url: URL) async -> Bool {
        let fileReader = fileReader
        return await Task.detached(priority: .userInitiated) {
            fileReader.isDirectory(at: url)
        }.value
    }

    /// Enter で確定したときのみ走る(ディレクトリ列挙を伴いうる)ため、
    /// stat の繰り返しを MainActor の外へ逃がす。
    func resolveFileToOpen(at url: URL) async -> URL? {
        let fileReader = fileReader
        return await Task.detached(priority: .userInitiated) {
            SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader)
        }.value
    }
}
