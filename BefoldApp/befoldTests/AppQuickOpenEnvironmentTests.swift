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

    private func makeEnvironment(
        gitIndex: any GitFileIndexing,
        currentFileURL: URL?
    ) -> AppQuickOpenEnvironment {
        let defaults = makeIsolatedDefaults(prefix: "AppQuickOpenEnvironmentTests")
        return AppQuickOpenEnvironment(
            gitIndex: gitIndex,
            recentDocumentsStore: RecentDocumentsStore(defaults: defaults),
            bookmarkStore: BookmarkStore(defaults: defaults),
            hiddenFilesPreference: HiddenFilesPreference(defaults: defaults),
            currentFileURL: currentFileURL
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

        let entries = await environment.directoryEntries(in: temporary.url)

        #expect(entries.map(\.lastPathComponent) == ["a.md"])
    }
}
