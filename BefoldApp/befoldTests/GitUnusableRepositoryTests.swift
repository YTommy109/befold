@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// libgit2 が開けないリポジトリ（partial clone / reftable / 未知の `extensions.*`）で、
/// git 機能が**一律に**無効化されることを固定する。
///
/// TASK-435 の移行中は読み手ごとに実装が入れ替わったため、「ルート解決だけ諦めるが
/// ステータスと差分は動く」という中間状態が成立しえた（TASK-435.2 の申し送り）。
/// 全実装が libgit2 へ揃った今、その不整合が無いことをここで担保する。
///
/// 実 git を起動しない。`.git/` を手で組み立てるフィクスチャなので、判定が
/// 手元の git のバージョンや壁時計に左右されない。
struct GitUnusableRepositoryTests {
    private func makeUnusableRepository(in directory: URL, extensionEntry: String) throws {
        try GitLibraryTests.makeUnopenableRepository(in: directory, extensionEntry: extensionEntry)
    }

    /// 「開けなかった」は「答えが確定した」ではないため、いずれの読み手も
    /// キャッシュ可能な確定値（`.notARepository` / 空スナップショット）を返してはならない。
    @Test("開けないリポジトリでは 3 つの読み手がそろって不明・縮退を返す", arguments: [
        "partialclone = origin",
        "refstorage = reftable",
        "somethingUnknown = 1",
    ])
    func degradesUniformlyForUnusableRepository(extensionEntry: String) throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnusableRepository(in: temp.url, extensionEntry: extensionEntry)
        let file = temp.url.appendingPathComponent("a.md")
        try "# a\n".write(to: file, atomically: true, encoding: .utf8)

        // ルート解決: 不明（キャッシュ不可）。管理外と確定させない。
        #expect(GitRepository().root(forFileAt: file) == .undetermined)
        // ステータス: nil（キャッシュ不可）。空スナップショットは「確定して変更なし」を意味する。
        #expect(GitStatusReader().status(forRepositoryAt: temp.url) == nil)
        // 差分: nil（キャッシュ不可）。
        #expect(GitDiffReader().diff(forFileAt: file, in: temp.url) == nil)
        // 比較起点: nil（起点が分からない）。
        #expect(GitComparisonBaseResolver().comparisonBase(forRepositoryAt: temp.url) == nil)
        // 追跡ファイル索引・worktree 一覧も空へ縮退する（Quick Open はディレクトリ走査へ落ちる）。
        #expect(GitRepository().trackedFiles(at: temp.url) == nil)
        #expect(GitRepository().worktrees(forRoot: temp.url).isEmpty)
    }

    /// 縮退の**表示**側。扱えないリポジトリでは基準ディレクトリの種別が
    /// 「通常フォルダ」ではなく「扱えないリポジトリ」になる(TASK-438.1)。
    /// キャッシュ層(`GitCommandFileIndex`)を通しても情報が `URL?` へ潰れないことを、
    /// 実フィクスチャで確かめる。
    @Test("扱えないリポジトリは基準ディレクトリの種別で通常フォルダと区別される")
    func baseDirectoryKindDistinguishesUnusableRepository() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnusableRepository(in: temp.url, extensionEntry: "partialclone = origin")

        let index = GitCommandFileIndex()
        let lookup = index.repositoryRootLookup(forDirectoryAt: temp.url)

        #expect(lookup == .undetermined)
        #expect(index.repositoryRoot(forDirectoryAt: temp.url) == nil)
        let descriptor = BaseDirectoryDescriptor(rootLookup: lookup, workspaceRoot: temp.url)
        #expect(descriptor.kind == .unusableRepository)
    }

    /// 縮退はモーダルを出さずに済むこと（ADR 0005 の Fallback）。呼び出しを繰り返しても
    /// クラッシュせず、同じ値を返し続ける。
    @Test("開けないリポジトリを繰り返し読んでもクラッシュしない")
    func repeatedReadsAreStable() throws {
        let temp = try TempDir()
        defer { withExtendedLifetime(temp) {} }
        try makeUnusableRepository(in: temp.url, extensionEntry: "partialclone = origin")
        let file = temp.url.appendingPathComponent("a.md")
        try "# a\n".write(to: file, atomically: true, encoding: .utf8)

        for _ in 0 ..< 20 {
            #expect(GitStatusReader().status(forRepositoryAt: temp.url) == nil)
            #expect(GitDiffReader().diff(forFileAt: file, in: temp.url) == nil)
        }
    }
}
