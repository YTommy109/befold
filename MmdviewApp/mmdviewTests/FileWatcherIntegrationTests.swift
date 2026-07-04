import Foundation
@testable import mmdview
import Testing

@Suite
struct FileWatcherIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func detectsFileModification() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // ファイル内容を変更
            try? "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

            // コールバック発火を待つ
            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileDeletion() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // ファイルを削除
            try? FileManager.default.removeItem(at: file)

            // コールバック発火を待つ
            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsAtomicSave() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // アトミック保存（一時ファイル → rename）をシミュレート
            let tmpFile = tmp.url.appendingPathComponent(".test.mmd.tmp")
            try? "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
            _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

            // コールバック発火を待つ
            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
    }

    /// 削除 → 同名再作成後の変更でもコールバックが発火することを検証する。
    /// ディレクトリ監視がファイルの再作成を検知してファイル監視を再開する経路の回帰テスト。
    @Test(.timeLimit(.minutes(1)))
    func detectsChangeAfterRecreation() async throws {
        let tmp = try TempDir()
        defer { withExtendedLifetime(tmp) {} }
        let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

        // 再作成後の変更で発火した最初のコールバックだけを検証対象にする。
        // 発火は 1 回以上あり得るため fired ガードで confirm() を 1 回に抑える
        // （範囲指定の expectedCount は Swift 6.0 の Swift Testing に無いため使わない）。
        // armed / fired は @Sendable クロージャに捕捉された後に書き換えるため、
        // 参照型（TestFlag）に包んで「captured var の後続変更」警告を避ける。
        await confirmation { confirm in
            let armed = TestFlag()
            let fired = TestFlag()
            let watcher = FileWatcher(path: file) {
                if armed.isSet, !fired.isSet {
                    fired.isSet = true
                    confirm()
                }
            }

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // ファイルを削除（ファイル監視ソースが解放される）
            try? FileManager.default.removeItem(at: file)
            try? await Task.sleep(for: .seconds(0.5))

            // 同名で再作成（ディレクトリ監視が検知してファイル監視を再開する）
            try? "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)
            // 監視再開と、再作成に伴う先行コールバックの消化を待つ
            try? await Task.sleep(for: .seconds(0.5))

            // ここから先のコールバックのみを検証対象にする
            armed.isSet = true

            // 再作成後の変更 → 監視が再開していればコールバックが発火する
            try? "graph TD; A-->C".write(to: file, atomically: false, encoding: .utf8)

            // コールバック発火を待つ
            try? await Task.sleep(for: .seconds(3))
            watcher.stop()
        }
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
        try? await Task.sleep(for: .seconds(1))
        #expect(renamed.url?.lastPathComponent == "renamed.mmd")

        // ここから先の onChange のみ検証対象にする
        armed.isSet = true
        // 追従後の新パスへの変更が検知される
        try "graph TD; A-->C".write(to: newFile, atomically: false, encoding: .utf8)
        try? await Task.sleep(for: .seconds(1))
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
        try? await Task.sleep(for: .seconds(1))
        #expect(renamed.url?.path == moved.resolvingSymlinksInPath().path)

        // 新しい親ディレクトリ基準で監視が張り直され、移動後の変更も検知される
        armed.isSet = true
        try "graph TD; A-->C".write(to: moved, atomically: false, encoding: .utf8)
        try? await Task.sleep(for: .seconds(1))
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

        try? await Task.sleep(for: .seconds(1.5))
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
            .appendingPathComponent("mmdview-test-\(UUID().uuidString)")
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

        nonisolated(unsafe) var callbackFired = false

        let watcher = FileWatcher(path: file) {
            callbackFired = true
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // 監視を停止してからファイルを変更
        watcher.stop()
        try "graph TD; A-->C".write(to: file, atomically: true, encoding: .utf8)

        // 十分待ってもコールバックが呼ばれないこと
        try? await Task.sleep(for: .seconds(1))
        #expect(!callbackFired)
    }
}

/// テスト内で @Sendable クロージャに捕捉された後に安全に書き換えるための可変フラグ。
/// 参照型にすることで捕捉した参照自体は不変のまま中身だけを更新でき、
/// 「sendable closure に捕捉した var の後続変更」警告を避ける。
private final class TestFlag: @unchecked Sendable {
    var isSet = false
}

/// rename コールバックで受け取った URL を @Sendable クロージャ越しに保持するための可変ボックス。
private final class RenamedBox: @unchecked Sendable {
    var url: URL?
}
