@testable import befold
import Foundation
import Testing

@Suite(.serialized)
struct FileWatcherIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func detectsFileModification() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = TestFlag()
        let watcher = FileWatcher(path: file) {
            changed.isSet = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // ファイル内容を変更
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // コールバック発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { changed.isSet }
        #expect(changed.isSet)
        watcher.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileDeletion() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = TestFlag()
        let watcher = FileWatcher(path: file) {
            changed.isSet = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // ファイルを削除
        try FileManager.default.removeItem(at: file)

        // コールバック発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { changed.isSet }
        #expect(changed.isSet)
        watcher.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsAtomicSave() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let changed = TestFlag()
        let watcher = FileWatcher(path: file) {
            changed.isSet = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // アトミック保存（一時ファイル → rename）をシミュレート
        let tmpFile = tmp.url.appendingPathComponent(".test.mmd.tmp")
        try "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

        // コールバック発火を待つ（ポーリングで CI 遅延に対応）
        await waitUntil { changed.isSet }
        #expect(changed.isSet)
        watcher.stop()
    }

    /// 削除 → 同名再作成後の変更でもコールバックが発火することを検証する。
    /// ディレクトリ監視がファイルの再作成を検知してファイル監視を再開する経路の回帰テスト。
    @Test(.timeLimit(.minutes(1)))
    func detectsChangeAfterRecreation() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let armed = TestFlag()
        let changed = TestFlag()
        let watcher = FileWatcher(path: file) {
            if armed.isSet { changed.isSet = true }
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // ファイルを削除（ファイル監視ソースが解放される）
        try FileManager.default.removeItem(at: file)
        try? await Task.sleep(for: .seconds(0.5))

        // 同名で再作成（ディレクトリ監視が検知してファイル監視を再開する）
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(0.5))

        // ここから先のコールバックのみを検証対象にする
        armed.isSet = true

        // 監視再開が遅れてもリトライで検知できるよう、発火するまで書き込みを繰り返す
        await waitUntilWithRetry(timeout: 15, action: {
            try? "graph TD; A-->\(Int.random(in: 0 ... 999))"
                .write(to: file, atomically: false, encoding: .utf8)
        }, until: {
            changed.isSet
        })
        #expect(changed.isSet)
        watcher.stop()
    }

    /// 同一ディレクトリ内での rename を検知し、新パスを通知したうえで
    /// 追従後の変更も検知できることを検証する。
    @Test(.timeLimit(.minutes(1)))
    func detectsRenameWithinSameDirectory() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let renamed = RenamedBox()
        let armed = TestFlag()
        let changed = TestFlag()
        let watcher = FileWatcher(path: file, onChange: {
            if armed.isSet { changed.isSet = true }
        }, onRename: { url in
            renamed.url = url
        })

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // 同一ディレクトリ内で別名へ rename
        let newFile = tmp.url.appendingPathComponent("renamed.mmd")
        try FileManager.default.moveItem(at: file, to: newFile)

        // rename 通知を待つ
        await waitUntil { renamed.url != nil }
        #expect(renamed.url?.lastPathComponent == "renamed.mmd")

        // ここから先の onChange のみ検証対象にする
        armed.isSet = true
        // 追従後の新パスへの変更が検知される
        try "graph TD; A-->C".write(to: newFile, atomically: false, encoding: .utf8)
        await waitUntil { changed.isSet }
        #expect(changed.isSet)

        watcher.stop()
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

        let renamed = RenamedBox()
        let armed = TestFlag()
        let changed = TestFlag()
        let watcher = FileWatcher(path: file, onChange: {
            if armed.isSet { changed.isSet = true }
        }, onRename: { url in
            renamed.url = url
        })

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // 別ディレクトリへ move
        let moved = dstDir.appendingPathComponent("test.mmd")
        try FileManager.default.moveItem(at: file, to: moved)

        // rename 通知を待つ
        await waitUntil { renamed.url != nil }
        #expect(renamed.url?.path == moved.resolvingSymlinksInPath().path)

        // 新しい親ディレクトリ基準で監視が張り直され、移動後の変更も検知される
        armed.isSet = true
        try "graph TD; A-->C".write(to: moved, atomically: false, encoding: .utf8)
        await waitUntil { changed.isSet }
        #expect(changed.isSet)

        watcher.stop()
    }

    /// エディタの save-by-rename（旧ファイルをバックアップへ退避し、同じパスに新ファイルを作る）が
    /// rename 扱いにならず、変更として通知されることを検証する。
    @Test(.timeLimit(.minutes(1)))
    func saveByRenameIsTreatedAsChangeNotRename() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        let renamed = RenamedBox()
        let armed = TestFlag()
        let changed = TestFlag()
        let watcher = FileWatcher(path: file, onChange: {
            if armed.isSet { changed.isSet = true }
        }, onRename: { url in
            renamed.url = url
        })

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))
        armed.isSet = true

        // save-by-rename をシミュレート: 監視中のファイルをバックアップへ rename し、
        // 同じパスに新しい内容のファイルを作る。元パスに新ファイルが存在するため rename 扱いにしない。
        let backup = tmp.url.appendingPathComponent("test.mmd.bak")
        try FileManager.default.moveItem(at: file, to: backup)
        try "graph TD; X-->Y".write(to: file, atomically: false, encoding: .utf8)

        // 変更として通知されるまで待つ
        await waitUntil { changed.isSet }
        // rename としては通知されない
        #expect(renamed.url == nil)
        // 変更としては通知される
        #expect(changed.isSet)

        watcher.stop()
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

        let callbackFired = TestFlag()

        let watcher = FileWatcher(path: file) {
            callbackFired.isSet = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // 監視を停止してからファイルを変更
        watcher.stop()
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // 十分待ってもコールバックが呼ばれないこと
        try? await Task.sleep(for: .seconds(1))
        #expect(!callbackFired.isSet)
    }
}

/// テスト内で @Sendable クロージャに捕捉された後に安全に書き換えるための可変フラグ。
/// 参照型にすることで捕捉した参照自体は不変のまま中身だけを更新でき、
/// 「sendable closure に捕捉した var の後続変更」警告を避ける。
/// コールバックスレッドとテスト本体（別スレッド）から無同期でアクセスされるため、
/// lock で読み書きを直列化してデータレースを防ぐ。
private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// rename コールバックで受け取った URL を @Sendable クロージャ越しに保持するための可変ボックス。
/// TestFlag と同様、コールバックスレッドとテスト本体から無同期でアクセスされるため lock で保護する。
private final class RenamedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URL?

    var url: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// 条件が true になるまでポーリングで待機する。CI 環境での DispatchSource イベント遅延に対応。
private func waitUntil(
    timeout: TimeInterval = 10,
    _ condition: @escaping @Sendable () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .seconds(0.05))
    }
}

/// 条件が true になるまで action を定期的に実行しながらポーリングで待機する。
/// 監視再開が遅れた場合でも後続の書き込みで検知できるようにするリトライパターン。
private func waitUntilWithRetry(
    timeout: TimeInterval = 15,
    interval: TimeInterval = 0.5,
    action: @escaping @Sendable () -> Void,
    until condition: @escaping @Sendable () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        action()
        let retryDeadline = Date().addingTimeInterval(interval)
        while !condition(), Date() < retryDeadline {
            try? await Task.sleep(for: .seconds(0.05))
        }
    }
}
