@testable import BefoldKit
import Foundation
import Testing

/// `repositoryRoot(forFileAt:)` の「末尾要素を落として親で判定する」契約を模した索引。
/// 本番の GitCommandFileIndex.resolvedRootLocked と同じく、引数の親ディレクトリが
/// リポジトリ配下かどうかでルートを返す。
private struct ParentDirectoryGitIndex: GitFileIndexing {
    /// リポジトリの作業ツリールート。この配下(自身を含む)なら root を返す。
    let root: URL

    func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
        nil
    }

    func repositoryRoot(forFileAt url: URL) -> URL? {
        let dir = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        return dir.starts(with: root.standardizedFileURL.pathComponents) ? root : nil
    }
}

@Suite("GitFileIndexing.repositoryRoot(forDirectoryAt:)")
struct GitFileIndexingDirectoryRootTests {
    private let index = ParentDirectoryGitIndex(root: URL(fileURLWithPath: "/Users/me/repo"))

    @Test("リポジトリルート自身を渡してもルートが返る(親で解決してしまわない)")
    func resolvesRepositoryRootItself() {
        #expect(
            index.repositoryRoot(forDirectoryAt: URL(fileURLWithPath: "/Users/me/repo"))
                == URL(fileURLWithPath: "/Users/me/repo")
        )
        // forFileAt: にディレクトリをそのまま渡すと 1 階層上で判定され nil になる。
        // この差を吸収するのが forDirectoryAt: の役割。
        #expect(index.repositoryRoot(forFileAt: URL(fileURLWithPath: "/Users/me/repo")) == nil)
    }

    @Test("リポジトリ配下のサブディレクトリでもルートが返る")
    func resolvesSubdirectory() {
        #expect(
            index.repositoryRoot(forDirectoryAt: URL(fileURLWithPath: "/Users/me/repo/docs"))
                == URL(fileURLWithPath: "/Users/me/repo")
        )
    }

    @Test("リポジトリ外のディレクトリでは nil")
    func returnsNilOutsideRepository() {
        #expect(index.repositoryRoot(forDirectoryAt: URL(fileURLWithPath: "/Users/me/notes")) == nil)
    }

    @Test("git を扱わない既定実装では nil のまま")
    func defaultImplementationReturnsNil() {
        struct NoGitIndex: GitFileIndexing {
            func trackedFileIndex(forFileAt _: URL) -> SuffixPathIndex? {
                nil
            }
        }
        #expect(NoGitIndex().repositoryRoot(forDirectoryAt: URL(fileURLWithPath: "/any")) == nil)
    }
}
