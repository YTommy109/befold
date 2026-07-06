import Foundation

/// テストごとに独立した UserDefaults スイートを用意する。
func makeIsolatedDefaults(prefix: String) -> UserDefaults {
    let suiteName = "\(prefix)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 一時ディレクトリを作成し、インスタンス解放時に削除する。
/// 非同期テストでディレクトリを使い終わる前に解放されないよう、
/// テスト冒頭で `defer { withExtendedLifetime(tmp) {} }` を置くこと。
final class TempDir: Sendable {
    let url: URL

    init(prefix: String = "befold-test") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// ディレクトリ内にファイルを作成して URL を返す。
    func file(named name: String, contents: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// ディレクトリ内にバイト列でファイルを作成して URL を返す。
    func file(named name: String, data: Data) throws -> URL {
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}

/// NSLock で保護したスレッドセーフな可変ボックス。
/// Sendable クロージャからのカウント・記録に使う。
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }

    func update(_ transform: @Sendable (inout Value) -> Void) {
        lock.withLock { transform(&value) }
    }
}
