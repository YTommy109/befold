@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// Quick Open の候補源が「メインスレッドを離れて」構築されることを固定する。
/// git サブプロセス・ディレクトリ再帰走査・`normalizedPathKey` の FS I/O は
/// すべて `gitIndex` の参照より後段に連なるため、索引が呼ばれたスレッドを見れば
/// 収集全体がどのスレッドで走ったかを判定できる。
@Suite
@MainActor
struct AppQuickOpenEnvironmentTests {
    /// 呼び出されたスレッドを記録するだけの索引。
    private final class ThreadRecordingGitIndex: GitFileIndexing, @unchecked Sendable {
        let box = LockedBox<[Bool]>([])

        func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
            box.update { $0.append(Thread.isMainThread) }
            return nil
        }

        func repositoryRoot(forFileAt _: URL) -> URL? {
            box.update { $0.append(Thread.isMainThread) }
            return nil
        }

        func warm(forFileAt _: URL) {}
    }

    /// 呼び出されたスレッドを記録するだけの FileReading ラッパー。isDirectory/resolveFileToOpen
    /// (SupportedFileResolver 経由のディレクトリ列挙)がメインスレッドを離れて走ることを検証する。
    private final class ThreadRecordingFileReader: FileReading, @unchecked Sendable {
        let box = LockedBox<[Bool]>([])
        private let base: any FileReading

        init(base: any FileReading = DefaultFileReader()) {
            self.base = base
        }

        func fileExists(at url: URL) -> Bool {
            base.fileExists(at: url)
        }

        func isExistingFile(at url: URL) -> Bool {
            base.isExistingFile(at: url)
        }

        func readString(from url: URL) throws -> String {
            try base.readString(from: url)
        }

        func readData(from url: URL) throws -> Data {
            try base.readData(from: url)
        }

        func isBinary(at url: URL) -> Bool {
            base.isBinary(at: url)
        }

        func fileSize(at url: URL) -> Int? {
            base.fileSize(at: url)
        }

        func modificationDate(at url: URL) -> Date? {
            base.modificationDate(at: url)
        }

        func isDirectory(at url: URL) -> Bool {
            box.update { $0.append(Thread.isMainThread) }
            return base.isDirectory(at: url)
        }
    }

    private func makeEnvironment(
        gitIndex: any GitFileIndexing,
        currentFileURL: URL?,
        fileReader: any FileReading = DefaultFileReader()
    ) -> AppQuickOpenEnvironment {
        let defaults = makeIsolatedDefaults(prefix: "AppQuickOpenEnvironmentTests")
        return AppQuickOpenEnvironment(
            gitIndex: gitIndex,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            sidebarDisplayPreference: SidebarDisplayPreference(defaults: defaults),
            currentFileURL: currentFileURL,
            fileReader: fileReader
        )
    }

    @Test("候補集合の構築はメインスレッドで走らない")
    func candidateSetIsBuiltOffTheMainThread() async throws {
        let temporary = try TempDir()
        let file = try temporary.file(named: "note.md", contents: "# note")
        let gitIndex = ThreadRecordingGitIndex()
        let environment = makeEnvironment(gitIndex: gitIndex, currentFileURL: file)

        _ = await environment.candidateSet()

        let observations = gitIndex.box.get()
        #expect(!observations.isEmpty)
        #expect(observations.allSatisfy { $0 == false })
    }

    @Test("ディレクトリ列挙は await を挟む(メインスレッドを占有しない)")
    func directoryEntriesAreEnumeratedAsynchronously() async throws {
        let temporary = try TempDir()
        _ = try temporary.file(named: "a.md", contents: "a")
        let environment = makeEnvironment(gitIndex: DisabledGitFileIndex(), currentFileURL: nil)

        let entries = try #require(await environment.directoryEntries(in: temporary.url))

        #expect(entries.map(\.lastPathComponent) == ["a.md"])
    }

    @Test("Tab補完のisDirectory判定はメインスレッドで走らない")
    func isDirectoryIsCheckedOffTheMainThread() async throws {
        let temporary = try TempDir()
        let fileReader = ThreadRecordingFileReader()
        let environment = makeEnvironment(
            gitIndex: DisabledGitFileIndex(), currentFileURL: nil, fileReader: fileReader
        )

        let result = await environment.isDirectory(temporary.url)

        #expect(result)
        let observations = fileReader.box.get()
        #expect(!observations.isEmpty)
        #expect(observations.allSatisfy { $0 == false })
    }

    @Test("Enter確定のresolveFileToOpen(ディレクトリ列挙)はメインスレッドで走らない")
    func resolveFileToOpenIsResolvedOffTheMainThread() async throws {
        let temporary = try TempDir()
        _ = try temporary.file(named: "a.md", contents: "a")
        let fileReader = ThreadRecordingFileReader()
        let environment = makeEnvironment(
            gitIndex: DisabledGitFileIndex(), currentFileURL: nil, fileReader: fileReader
        )

        let resolved = await environment.resolveFileToOpen(at: temporary.url)

        #expect(resolved?.lastPathComponent == "a.md")
        let observations = fileReader.box.get()
        #expect(!observations.isEmpty)
        #expect(observations.allSatisfy { $0 == false })
    }
}
