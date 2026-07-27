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
    private let hiddenFilesPreference: HiddenFilesPreference
    private let fileReader: any FileReading
    /// いま開いているファイル。ウィンドウが 1 枚も無ければ nil。
    private let currentFileURL: URL?

    init(
        gitIndex: any GitFileIndexing,
        recentDocumentsStore: RecentDocumentsStore,
        bookmarkStore: BookmarkStore,
        hiddenFilesPreference: HiddenFilesPreference,
        currentFileURL: URL?,
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.gitIndex = gitIndex
        self.recentDocumentsStore = recentDocumentsStore
        self.bookmarkStore = bookmarkStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.currentFileURL = currentFileURL
        self.fileReader = fileReader
    }

    var baseDirectory: URL? {
        currentFileURL?.deletingLastPathComponent()
    }

    var includingHiddenFiles: Bool {
        hiddenFilesPreference.showHiddenFiles
    }

    func candidateSet() -> QuickOpenCandidateSet {
        guard let currentFileURL else {
            // 開いているファイルが無ければ探す起点も無い。履歴とブックマークだけを出す。
            let home = FileManager.default.homeDirectoryForCurrentUser
            return QuickOpenCandidates.collect(
                root: home,
                anchorFile: home,
                gitIndex: DisabledGitFileIndex(),
                scanner: DirectoryFileScanner(maximumDepth: 0),
                recentURLs: recentDocumentsStore.recentURLs(),
                bookmarkedURLs: bookmarkStore.bookmarkedURLs(),
                includingHiddenFiles: includingHiddenFiles
            )
        }
        // ルート解決は索引に一本化する。ここで別の GitRepository を new して rev-parse を
        // 重ねず、collect が引く追跡ファイル索引と同じ 1 回の解決結果を共有する。
        let root = gitIndex.repositoryRoot(forFileAt: currentFileURL)
            ?? currentFileURL.deletingLastPathComponent()
        return QuickOpenCandidates.collect(
            root: root,
            anchorFile: currentFileURL,
            gitIndex: gitIndex,
            scanner: DirectoryFileScanner(),
            recentURLs: recentDocumentsStore.recentURLs(),
            bookmarkedURLs: bookmarkStore.bookmarkedURLs(),
            includingHiddenFiles: includingHiddenFiles
        )
    }

    func directoryEntries(in directory: URL) -> [URL] {
        // 列挙とソートは DirectoryLister の単一情報源へ委譲する。自前で
        // FileManager を叩くと返却順が未定義になり、候補順・選択位置・補完表記が
        // 非決定的になる。隠しファイルの出し分けは QuickOpenModel が入力に応じて
        // 決めるため、ここでは隠しファイルも含めた全件を名前昇順で返す。
        DirectoryLister.allEntriesSorted(in: directory)
    }

    func isDirectory(_ url: URL) -> Bool {
        fileReader.isDirectory(at: url)
    }

    func resolveFileToOpen(at url: URL) -> URL? {
        SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader)
    }
}
