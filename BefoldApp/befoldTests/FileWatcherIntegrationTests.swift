@testable import befold
import Foundation
import Testing

/// 統合テスト用の短い遅延。プロダクト既定の 0.2s では TSan スローダウン下で
/// 伝搬チェーンが長くなりタイムアウトしやすいため、テストでは短い値を注入して
/// 所要時間とマージンを改善する。
private let testDebounceDelay: TimeInterval = 0.05
private let testRenameSettleDelay: TimeInterval = 0.05

@Suite(.serialized)
struct FileWatcherIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func detectsFileModification() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = LockedBox(false)
        let watcher = FileWatcher(path: file, debounceDelay: testDebounceDelay) {
            changed.set(true)
        }
        defer { watcher.stop() }

        // 発火するまで書き込みを繰り返す（イベント取りこぼしに強い）
        await waitUntilWithRetry(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: true, encoding: .utf8)
        }, until: {
            changed.get()
        })
        #expect(changed.get())
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileDeletion() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = LockedBox(false)
        let watcher = FileWatcher(path: file, debounceDelay: testDebounceDelay) {
            changed.set(true)
        }
        defer { watcher.stop() }

        // 削除は一度きりの操作（冪等でない）。ファイル .delete とディレクトリ .write の
        // 両方でイベントが上がるため取りこぼしにくく、waitUntil のまま待つ。
        try FileManager.default.removeItem(at: file)

        // コールバック発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { changed.get() }
        #expect(changed.get())
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsAtomicSave() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = LockedBox(false)
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay
        ) {
            changed.set(true)
        }
        defer { watcher.stop() }

        // アトミック保存（一時ファイル → rename）を発火するまで繰り返す。
        // 毎回一時ファイルを作り直すので再試行しても冪等。
        await waitUntilWithRetry(action: {
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
    @Test(.timeLimit(.minutes(1)))
    func detectsChangeAfterRecreation() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let armed = LockedBox(false)
        let changed = LockedBox(false)
        let watcher = FileWatcher(path: file, debounceDelay: testDebounceDelay) {
            if armed.get() { changed.set(true) }
        }
        defer { watcher.stop() }

        // ファイルを削除（ファイル監視ソースが解放される）
        try FileManager.default.removeItem(at: file)
        try? await Task.sleep(for: .seconds(0.2))

        // 同名で再作成（ディレクトリ監視が検知してファイル監視を再開する）
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(0.2))

        // ここから先のコールバックのみを検証対象にする
        armed.set(true)

        // 監視再開が遅れてもリトライで検知できるよう、発火するまで書き込みを繰り返す
        await waitUntilWithRetry(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: false, encoding: .utf8)
        }, until: {
            changed.get()
        })
        #expect(changed.get())
    }

    /// 同一ディレクトリ内での rename を検知し、新パスを通知したうえで
    /// 追従後の変更も検知できることを検証する。
    @Test(.timeLimit(.minutes(1)))
    func detectsRenameWithinSameDirectory() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let renamed = LockedBox<URL?>(nil)
        let armed = LockedBox(false)
        let changed = LockedBox(false)
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay,
            onChange: {
                if armed.get() { changed.set(true) }
            },
            onRename: { url in
                renamed.set(url)
            }
        )
        defer { watcher.stop() }

        // 同一ディレクトリ内で別名へ rename。rename は一度きりの操作（冪等でない）で、
        // .rename イベントは確実に上がるため waitUntil のまま待つ。
        let newFile = tmp.url.appendingPathComponent("renamed.mmd")
        try FileManager.default.moveItem(at: file, to: newFile)

        // rename 通知を待つ
        await waitUntil { renamed.get() != nil }
        #expect(renamed.get()?.lastPathComponent == "renamed.mmd")

        // ここから先の onChange のみ検証対象にする
        armed.set(true)
        // 追従後の新パスへの変更を、発火するまで書き込みを繰り返して検知する
        await waitUntilWithRetry(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: newFile, atomically: false, encoding: .utf8)
        }, until: {
            changed.get()
        })
        #expect(changed.get())
    }

    /// 別ディレクトリへの move を検知し、新しい親ディレクトリ基準で監視が張り直され、
    /// 移動後の変更も検知できることを検証する。
    @Test(.timeLimit(.minutes(1)))
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
        let armed = LockedBox(false)
        let changed = LockedBox(false)
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay,
            onChange: {
                if armed.get() { changed.set(true) }
            },
            onRename: { url in
                renamed.set(url)
            }
        )
        defer { watcher.stop() }

        // 別ディレクトリへ move。move も一度きりの操作（冪等でない）で
        // .rename イベントは確実に上がるため waitUntil のまま待つ。
        let moved = dstDir.appendingPathComponent("test.mmd")
        try FileManager.default.moveItem(at: file, to: moved)

        // rename 通知を待つ
        await waitUntil { renamed.get() != nil }
        #expect(renamed.get()?.path == moved.resolvingSymlinksInPath().path)

        // 新しい親ディレクトリ基準で監視が張り直され、移動後の変更を
        // 発火するまで書き込みを繰り返して検知する
        armed.set(true)
        await waitUntilWithRetry(action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: moved, atomically: false, encoding: .utf8)
        }, until: {
            changed.get()
        })
        #expect(changed.get())
    }

    /// エディタの save-by-rename（旧ファイルをバックアップへ退避し、同じパスに新ファイルを作る）が
    /// rename 扱いにならず、変更として通知されることを検証する。
    @Test(.timeLimit(.minutes(1)))
    func saveByRenameIsTreatedAsChangeNotRename() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let renamed = LockedBox<URL?>(nil)
        let armed = LockedBox(false)
        let changed = LockedBox(false)
        let watcher = FileWatcher(
            path: file,
            debounceDelay: testDebounceDelay,
            renameSettleDelay: testRenameSettleDelay,
            onChange: {
                if armed.get() { changed.set(true) }
            },
            onRename: { url in
                renamed.set(url)
            }
        )
        defer { watcher.stop() }
        armed.set(true)

        // save-by-rename をシミュレート: 監視中のファイルをバックアップへ rename し、
        // 同じパスに新しい内容のファイルを作る。元パスに新ファイルが存在するため rename 扱いにしない。
        // 最初の 1 回で save-by-rename を再現し、以降は通常書き込みでリトライする。
        // 通常書き込みは rename を発生させないため、「rename としては通知されない」検証の意味は保たれる。
        let backup = tmp.url.appendingPathComponent("test.mmd.bak")
        try FileManager.default.moveItem(at: file, to: backup)
        let didSaveByRename = LockedBox(false)
        await waitUntilWithRetry(action: {
            if !didSaveByRename.get() {
                didSaveByRename.set(true)
                try? "graph TD; X-->Y".write(to: file, atomically: false, encoding: .utf8)
            } else {
                try? "graph TD; X-->\(Int.random(in: 0 ... 999))"
                    .write(to: file, atomically: false, encoding: .utf8)
            }
        }, until: {
            changed.get()
        })
        // rename としては通知されない
        #expect(renamed.get() == nil)
        // 変更としては通知される
        #expect(changed.get())
    }

    /// 存在しないファイルで初期化してもクラッシュせず、stop() も安全に呼べること
    @Test
    func watchingNonexistentFileDoesNotCrash() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("befold-test-\(UUID().uuidString)")
            .appendingPathComponent("nonexistent.mmd")

        let watcher = FileWatcher(path: file) {}
        // クラッシュしないこと自体が検証対象
        watcher.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopPreventsCallback() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let callbackFired = LockedBox(false)

        let watcher = FileWatcher(path: file, debounceDelay: testDebounceDelay) {
            callbackFired.set(true)
        }

        // 監視を停止してからファイルを変更
        watcher.stop()
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // 十分待ってもコールバックが呼ばれないこと（発火しないことの確認なので固定待ち）
        try? await Task.sleep(for: .seconds(1))
        #expect(!callbackFired.get())
    }
}
