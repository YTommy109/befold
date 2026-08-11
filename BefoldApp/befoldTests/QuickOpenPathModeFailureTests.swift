@testable import befold
import BefoldKit
import Foundation
import Testing

/// Quick Open のパスモードで、親ディレクトリを読み取れなかった場合の扱い(TASK-410)。
///
/// QuickOpenModelTests から分けているのは、型グループの行数(scripts/check-type-group-size.sh)を
/// 増やさないため。あちらは既にベースラインへ登録済みで、追記すると CI が落ちる。
@MainActor
struct QuickOpenPathModeFailureTests {
    /// 列挙の成否だけを差し替えられる最小の環境。
    private final class Environment: QuickOpenEnvironment {
        let baseDirectory: URL? = URL(fileURLWithPath: "/base")
        var includingHiddenFiles = false
        /// nil を返すディレクトリ(= 列挙に失敗する)。
        var failedDirectories: Set<String> = []
        var entries: [String: [URL]] = [:]

        func candidateSet() async -> QuickOpenCandidateSet {
            QuickOpenCandidateSet(candidates: [], isTruncated: false)
        }

        func directoryEntries(in directory: URL) async -> [URL]? {
            guard !failedDirectories.contains(directory.normalizedPathKey) else { return nil }
            return entries[directory.normalizedPathKey] ?? []
        }

        func isDirectory(_: URL) async -> Bool {
            false
        }

        func resolveFileToOpen(at url: URL) async -> URL? {
            url
        }
    }

    private func makeModel(_ environment: Environment) -> QuickOpenModel {
        QuickOpenModel(environment: environment, onOpen: { _ in })
    }

    /// 「一致なし」と「読み取れない」で利用者の次の一手が違う(打ち直す / 諦める)。
    /// 同じ文言に畳むと、打ち直しても直らない入力を打ち直させることになる。
    @Test("パスモードで列挙に失敗したら、候補 0 件とは別の通知を出す")
    func distinguishesEnumerationFailureFromNoMatches() async {
        let environment = Environment()
        environment.failedDirectories = [URL(fileURLWithPath: "/unreadable").normalizedPathKey]
        let model = makeModel(environment)

        model.queryText = "/unreadable/"
        await model.waitForPendingWork()

        #expect(model.showsEnumerationFailure)
        #expect(!model.showsNoMatches)
    }

    /// 読めた上で候補が 0 件なのは正常な状態。失敗の通知を出してはならない。
    @Test("読めて候補が 0 件なら、失敗ではなく「一致なし」を出す")
    func reportsNoMatchesWhenDirectoryIsReadable() async {
        let model = makeModel(Environment())

        model.queryText = "/empty/"
        await model.waitForPendingWork()

        #expect(!model.showsEnumerationFailure)
        #expect(model.showsNoMatches)
    }

    /// 失敗を候補と別に持って更新を忘れると、fuzzy へ戻った後も
    /// 「読み取れません」が出続ける。`apply(_:listingFailed:)` の必須引数で塞いでいる。
    @Test("失敗の直後に別の入力へ移ったら、失敗の表示は残らない")
    func failureDoesNotSurviveNextQuery() async {
        let environment = Environment()
        environment.failedDirectories = [URL(fileURLWithPath: "/unreadable").normalizedPathKey]
        let model = makeModel(environment)

        model.queryText = "/unreadable/"
        await model.waitForPendingWork()
        #expect(model.showsEnumerationFailure)

        model.queryText = "readme"

        #expect(!model.showsEnumerationFailure)
    }
}
