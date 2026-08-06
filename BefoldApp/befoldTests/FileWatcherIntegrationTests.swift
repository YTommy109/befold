@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 統合テスト用の短い遅延。プロダクト既定の 0.2s では TSan スローダウン下で
/// 伝搬チェーンが長くなりタイムアウトしやすいため、テストでは短い値を注入して
/// 所要時間とマージンを改善する。
private let testDebounceDelay: TimeInterval = 0.05
private let testRenameSettleDelay: TimeInterval = 0.05

@Suite
struct FileWatcherIntegrationTests {
    /// 「TempDir に初期ファイルを作成し、短い debounce/renameSettleDelay で FileWatcher を
    /// 張る」定型(6 回反復)を共通化する。detectsMoveToAnotherDirectory は src/dst 2 ディレクトリを
    /// 使う特殊なセットアップのため対象外。
    /// 呼び出し側は返り値の tmp を `defer { withExtendedLifetime(tmp) {} }` で、
    /// watcher を `defer { watcher.stop() }`(または明示的な `watcher.stop()`)で解放すること。
    private func makeWatchedTempFile(
        onChange: @escaping @MainActor @Sendable () -> Void,
        onRename: (@MainActor @Sendable (URL) -> Void)? = nil
    ) throws -> (tmp: TempDir, file: URL, watcher: FileWatcher) {
        let tmp = try TempDir()
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay,
            onChange: onChange,
            onRename: onRename
        )
        return (tmp, file, watcher)
    }

    @Test(testTimeLimit())
    func detectsFileDeletion() async throws {
        let count = LockedBox(0)
        let (tmp, file, watcher) = try makeWatchedTempFile(onChange: { count.update { $0 += 1 } })
        defer { withExtendedLifetime(tmp) {} }
        defer { watcher.stop() }

        // 削除は一度きり（エッジトリガー）で再実行できないため、書き込みプローブで
        // 監視 arm を確認してから削除する。基準値は静穏化後のコールバック回数。
        let baseline = await confirmWatcherArmed(file: file, callbackCount: count)

        try FileManager.default.removeItem(at: file)

        // 削除後の発火（基準値からの増加）を待つ
        await waitForMainActorDelivery { count.get() > baseline }
        #expect(count.get() > baseline)
    }

    @Test(testTimeLimit())
    func detectsAtomicSave() async throws {
        let changed = LockedBox(false)
        let (tmp, file, watcher) = try makeWatchedTempFile(onChange: { changed.set(true) })
        defer { withExtendedLifetime(tmp) {} }
        defer { watcher.stop() }

        // アトミック保存（一時ファイル → rename）を発火するまで繰り返す。
        // 毎回一時ファイルを作り直すので再試行しても冪等で、arm レースも救済される。
        await waitForMainActorDelivery(action: {
            let tmpFile = tmp.url.appendingPathComponent(".test.mmd.tmp")
            try? "graph TD; X-->\(Int.random(in: 0 ... 999))"
                .write(to: tmpFile, atomically: false, encoding: .utf8)
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)
        }, until: {
            changed.get()
        })
        #expect(changed.get())
    }

    /// 削除 → 同名再作成後の変更でもコールバックが発火することを検証する。
    /// ディレクトリ監視がファイルの再作成を検知してファイル監視を再開する経路の回帰テスト。
    @Test(testTimeLimit())
    func detectsChangeAfterRecreation() async throws {
        let count = LockedBox(0)
        let (tmp, file, watcher) = try makeWatchedTempFile(onChange: { count.update { $0 += 1 } })
        defer { withExtendedLifetime(tmp) {} }
        defer { watcher.stop() }

        // 削除を確実に捕捉するため、監視 arm を確認してから削除する。
        _ = await confirmWatcherArmed(file: file, callbackCount: count)

        // ファイルを削除（.delete を捕捉してファイル監視ソースが解放される）。
        // 解放が反映されるまで（コールバック増加）を待ってから再作成する。
        let beforeDelete = count.get()
        try FileManager.default.removeItem(at: file)
        await waitForMainActorDelivery { count.get() > beforeDelete }

        // 同名で再作成（ディレクトリ監視が検知してファイル監視を再開する）。
        // ディレクトリソースは file source より前に登録されるため、arm 確認済みなら
        // 再作成の .write も捕捉される。
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        // 再作成後の変更のみを検証対象にするため、ここで基準値を取り直す。
        // 待機時間はテスト debounce(testDebounceDelay)の 3 倍。デバウンス由来の
        // 遅延コールバックが収まるのを待つ基準は DebouncerTests の settlePeriod
        // (= delay * 3)と同じ。
        try? await Task.sleep(for: .seconds(testDebounceDelay * 3))
        let baseline = count.get()

        // 監視再開が遅れてもリトライで検知できるよう、発火するまで書き込みを繰り返す
        await waitForMainActorDelivery(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: false, encoding: .utf8)
        }, until: {
            count.get() > baseline
        })
        #expect(count.get() > baseline)
    }

    /// 同一ディレクトリ内での rename を検知し、新パスを通知したうえで
    /// 追従後の変更も検知できることを検証する。
    @Test(testTimeLimit())
    func detectsRenameWithinSameDirectory() async throws {
        let renamed = LockedBox<URL?>(nil)
        let count = LockedBox(0)
        let (tmp, file, watcher) = try makeWatchedTempFile(
            onChange: { count.update { $0 += 1 } },
            onRename: { url in renamed.set(url) }
        )
        defer { withExtendedLifetime(tmp) {} }
        defer { watcher.stop() }

        // rename は一度きり（エッジトリガー）で再実行できないため、監視 arm を確認してから
        // rename する。renamed ボックスは onChange と独立なのでプローブの影響を受けない。
        _ = await confirmWatcherArmed(file: file, callbackCount: count)

        // 同一ディレクトリ内で別名へ rename
        let newFile = tmp.url.appendingPathComponent("renamed.mmd")
        try FileManager.default.moveItem(at: file, to: newFile)

        // rename 通知を待つ
        await waitForMainActorDelivery { renamed.get() != nil }
        #expect(renamed.get()?.lastPathComponent == "renamed.mmd")

        // 追従後（監視は新パスへ張り直され再び登録レースが発生する）の変更を、
        // 発火するまで書き込みを繰り返して検知する
        let baseline = count.get()
        await waitForMainActorDelivery(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: newFile, atomically: false, encoding: .utf8)
        }, until: {
            count.get() > baseline
        })
        #expect(count.get() > baseline)
    }

    /// 別ディレクトリへの move を検知し、新しい親ディレクトリ基準で監視が張り直され、
    /// 移動後の変更も検知できることを検証する。
    @Test(testTimeLimit())
    func detectsMoveToAnotherDirectory() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let srcDir = tmp.url.appendingPathComponent("src")
        let dstDir = tmp.url.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let file = srcDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        let renamed = LockedBox<URL?>(nil)
        let count = LockedBox(0)
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay,
            onChange: {
                count.update { $0 += 1 }
            },
            onRename: { url in
                renamed.set(url)
            }
        )
        defer { watcher.stop() }

        // move も一度きり（エッジトリガー）で再実行できないため、監視 arm を確認してから move する。
        _ = await confirmWatcherArmed(file: file, callbackCount: count)

        // 別ディレクトリへ move
        let moved = dstDir.appendingPathComponent("test.mmd")
        try FileManager.default.moveItem(at: file, to: moved)

        // rename 通知を待つ
        await waitForMainActorDelivery { renamed.get() != nil }
        #expect(renamed.get()?.path == moved.resolvingSymlinksInPath().path)

        // 新しい親ディレクトリ基準で監視が張り直され、移動後の変更を
        // 発火するまで書き込みを繰り返して検知する
        let baseline = count.get()
        await waitForMainActorDelivery(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: moved, atomically: false, encoding: .utf8)
        }, until: {
            count.get() > baseline
        })
        #expect(count.get() > baseline)
    }

    /// エディタの save-by-rename（旧ファイルをバックアップへ退避し、同じパスに新ファイルを作る）が
    /// rename 扱いにならず、変更として通知されることを検証する。
    @Test(testTimeLimit())
    func saveByRenameIsTreatedAsChangeNotRename() async throws {
        let renamed = LockedBox<URL?>(nil)
        let count = LockedBox(0)
        let (tmp, file, watcher) = try makeWatchedTempFile(
            onChange: { count.update { $0 += 1 } },
            onRename: { url in renamed.set(url) }
        )
        defer { withExtendedLifetime(tmp) {} }
        defer { watcher.stop() }

        // save-by-rename の .rename も一度きり。監視 arm を確認してから実行する。
        // arm を保証することで、万一 rename と誤判定された場合に renamed が設定され、
        // 「rename としては通知されない」検証が偽陽性でパスするのを防ぐ。
        let baseline = await confirmWatcherArmed(file: file, callbackCount: count)

        // save-by-rename をシミュレート: 監視中のファイルをバックアップへ rename し、
        // 同じパスに新しい内容のファイルを作る。元パスに新ファイルが存在するため rename 扱いにしない。
        // 初回で save-by-rename を再現し、以降は通常書き込みでリトライする（rename を
        // 発生させないため「rename としては通知されない」検証の意味は保たれる）。
        let backup = tmp.url.appendingPathComponent("test.mmd.bak")
        try FileManager.default.moveItem(at: file, to: backup)
        try "graph TD; X-->Y".write(to: file, atomically: false, encoding: .utf8)
        await waitForMainActorDelivery(action: {
            try? "graph TD; X-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: false, encoding: .utf8)
        }, until: {
            count.get() > baseline
        })
        // rename としては通知されない
        #expect(renamed.get() == nil)
        // 変更としては通知される
        #expect(count.get() > baseline)
    }

    /// 存在しないファイルで初期化してもクラッシュせず、stop() も安全に呼べること
    @Test
    func watchingNonexistentFileDoesNotCrash() throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = tmp.url.appendingPathComponent("no-such-dir/nonexistent.mmd")

        let watcher = FileWatcher(path: file) {}
        // クラッシュしないこと自体が検証対象
        watcher.stop()
    }

    @Test(testTimeLimit())
    func stopPreventsCallback() async throws {
        let callbackFired = LockedBox(false)
        let (tmp, file, watcher) = try makeWatchedTempFile(onChange: { callbackFired.set(true) })
        defer { withExtendedLifetime(tmp) {} }

        // 監視を停止してからファイルを変更
        watcher.stop()
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // 十分待ってもコールバックが呼ばれないこと（発火しないことの確認なので固定待ち）。
        // atomically: true の書き込みは rename 経由(.rename → renameSettleDelay →
        // resolveRename → scheduleNotify → debounce → MainActor、FileWatcher.swift:108-160)
        // のため、万一 stop() がリークしても発火し得る最大経路長
        // testRenameSettleDelay + testDebounceDelay を基準に + 0.3s の余裕を持たせ、
        // 時限の境界を確実に跨ぐ(docs/dev/coding_rule.md 参照)。
        try? await Task.sleep(for: .seconds(testRenameSettleDelay + testDebounceDelay + 0.3))
        #expect(!callbackFired.get())
    }
}
