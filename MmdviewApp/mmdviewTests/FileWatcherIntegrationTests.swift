import Foundation
@testable import mmdview
import Testing

@Suite
struct FileWatcherIntegrationTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsFileModification() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

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
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

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
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

        await confirmation { confirm in
            let watcher = FileWatcher(path: file) {
                confirm()
            }

            // 初期化完了を待つ
            try? await Task.sleep(for: .seconds(0.3))

            // アトミック保存（一時ファイル → rename）をシミュレート
            let tmpFile = tempDir.appendingPathComponent(".test.mmd.tmp")
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
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

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
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let file = tempDir.appendingPathComponent("test.mmd")
        try "graph TD; A-->B".write(to: file, atomically: true, encoding: .utf8)

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
