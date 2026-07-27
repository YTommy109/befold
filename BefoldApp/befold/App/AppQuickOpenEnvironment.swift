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
    private let repository: any GitRepositoryReading
    private let fileReader: any FileReading
    /// いま開いているファイル。ウィンドウが 1 枚も無ければ nil。
    private let currentFileURL: URL?

    init(
        gitIndex: any GitFileIndexing,
        recentDocumentsStore: RecentDocumentsStore,
        bookmarkStore: BookmarkStore,
        hiddenFilesPreference: HiddenFilesPreference,
        currentFileURL: URL?,
        repository: any GitRepositoryReading = GitRepository(),
        fileReader: any FileReading = DefaultFileReader()
    ) {
        self.gitIndex = gitIndex
        self.recentDocumentsStore = recentDocumentsStore
        self.bookmarkStore = bookmarkStore
        self.hiddenFilesPreference = hiddenFilesPreference
        self.currentFileURL = currentFileURL
        self.repository = repository
        self.fileReader = fileReader
    }

    var baseDirectory: URL? {
        currentFileURL?.deletingLastPathComponent()
    }

    var includingHiddenFiles: Bool {
        hiddenFilesPreference.showHiddenFiles
    }

    func candidateSet() -> QuickOpenCandidateSet {
        guard let root = searchRoot else {
            // 開いているファイルが無ければ探す起点も無い。履歴とブックマークだけを出す。
            return QuickOpenCandidates.collect(
                root: FileManager.default.homeDirectoryForCurrentUser,
                gitIndex: DisabledGitFileIndex(),
                scanner: DirectoryFileScanner(maximumDepth: 0),
                recentURLs: recentDocumentsStore.recentURLs(),
                bookmarkedURLs: bookmarkStore.bookmarkedURLs(),
                includingHiddenFiles: includingHiddenFiles
            )
        }
        return QuickOpenCandidates.collect(
            root: root,
            gitIndex: gitIndex,
            scanner: DirectoryFileScanner(),
            recentURLs: recentDocumentsStore.recentURLs(),
            bookmarkedURLs: bookmarkStore.bookmarkedURLs(),
            includingHiddenFiles: includingHiddenFiles
        )
    }

    func directoryEntries(in directory: URL) -> [URL] {
        // 隠しファイルの出し分けは QuickOpenModel が入力に応じて決めるため、ここでは全件返す。
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: []
        )) ?? []
    }

    func isDirectory(_ url: URL) -> Bool {
        fileReader.isDirectory(at: url)
    }

    func resolveFileToOpen(at url: URL) -> URL? {
        SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader)
    }

    /// 候補を集める起点。git 管理下ならリポジトリルート、そうでなければ開いているファイルのディレクトリ。
    private var searchRoot: URL? {
        guard let currentFileURL else { return nil }
        return repository.root(forFileAt: currentFileURL).foundRoot
            ?? currentFileURL.deletingLastPathComponent()
    }
}
