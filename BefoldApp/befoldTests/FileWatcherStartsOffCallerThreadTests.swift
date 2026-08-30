import Foundation
import Testing

/// 「`FileWatcher` の監視開始は呼び出し元のスレッドを塞がない」という規則を、
/// `init` 本体に `queue.sync` が現れないことで固定する(TASK-566)。
///
/// `startMonitors` は監視対象とその親ディレクトリを `open()` で開く。この呼び出しを
/// `queue.sync` で待つと syscall が呼び出し元(多くはメインスレッド)で同期に走り、
/// iCloud Drive やネットワークボリュームのように open が遅い場所ではアプリ全体が
/// 止まる。実測(TASK-566 / 2026-08-29)ではセッション復元中の 3 秒のサンプル
/// 2611/2611 がメインスレッドの `open()` だった。
///
/// **このテストが測るのはソースの字面であって、メインスレッドが塞がらないこと
/// そのものではない。** 振る舞いの確認は手動手順(タスクの Implementation Notes)が
/// 担う。ここは「元へ戻す変更が無言で通らない」ことだけを保証する
/// (`SidebarRowAssemblySingleSourceTests` と同じ、規則を数えて固定する形)。
///
/// `stop()` の `queue.sync` は対象外。あちらは監視キュー上から呼ばれず、
/// 解放の完了を待つ必要があるため sync が正しい。
@Suite
struct FileWatcherStartsOffCallerThreadTests {
    private static let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold/FileWatching/FileWatcher.swift")

    /// `init(...)` の宣言から、同じインデントで閉じる `}` までの行。
    private static func initBody() throws -> [String] {
        let lines = try String(contentsOf: source, encoding: .utf8).split(
            separator: "\n", omittingEmptySubsequences: false
        ).map(String.init)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "init(" }) else {
            throw BodyError.initNotFound
        }
        guard let end = lines[start...].firstIndex(where: { $0 == "    }" }) else {
            throw BodyError.initEndNotFound
        }
        return Array(lines[start ... end])
    }

    private enum BodyError: Error {
        case initNotFound
        case initEndNotFound
    }

    @Test("FileWatcher.init が監視開始を queue.sync で待たない")
    func initDoesNotBlockOnMonitorStart() throws {
        let body = try Self.initBody()
        let blocking = body.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { return false }
            return trimmed.contains("queue.sync")
        }
        #expect(
            blocking.isEmpty,
            """
            FileWatcher.init が queue.sync で監視開始を待っている。open() が遅いパスで
            アプリ全体が固まる(TASK-566)。queue.async のまま、開始直後の取りこぼしは
            startMonitorsAndCatchUp の通知で埋めること。
            """
        )
    }

    /// 非同期化で開く「まだ監視していない」区間を埋める通知が消えていないことも見る。
    /// 片方だけ残ると、固まらないが変更を取りこぼす形になる。
    @Test("監視開始の直後に取りこぼしを埋める通知が出る")
    func startSchedulesCatchUpNotification() throws {
        let text = try String(contentsOf: Self.source, encoding: .utf8)
        #expect(text.contains("startMonitorsAndCatchUp"))
        #expect(text.contains("queue.async { self.startMonitorsAndCatchUp() }"))
    }
}
