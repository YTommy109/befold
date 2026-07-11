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

    /// - Parameter base: 作成先の親ディレクトリ。省略時はシステム一時ディレクトリ。
    ///   `navigateToFolder` はホームディレクトリ配下のみ許可するため、それをテストする
    ///   場合はホームディレクトリ配下(例: `homeDirectoryForCurrentUser`)を渡す。
    init(prefix: String = "befold-test", base: URL = FileManager.default.temporaryDirectory) throws {
        url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
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

/// ポーリング待機の既定タイムアウト。`BEFOLD_TEST_TIMEOUT_SECONDS` が設定されていれば
/// それを秒数として使い、なければ `fallback` 秒を使う。ThreadSanitizer ジョブなど
/// スローダウンの大きい環境で CI 側からタイムアウトを延長できるようにする。
func testTimeout(fallback seconds: Double) -> Duration {
    let raw = ProcessInfo.processInfo.environment["BEFOLD_TEST_TIMEOUT_SECONDS"]
    if let raw, let override = Double(raw) {
        return .seconds(override)
    }
    return .seconds(seconds)
}

/// 条件が true になるまでポーリングで待機する。CI 環境でのファイル監視イベントや
/// タイマー発火の遅延に対応するため、固定 sleep ではなく条件成立を待つ。
func waitUntil(
    timeout: Duration = testTimeout(fallback: 10),
    _ condition: @escaping @Sendable () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(50))
    }
}

/// `waitUntil` の MainActor 版。`@Observable` ストアなど MainActor 隔離のプロパティを
/// 参照する条件は Sendable クロージャにできないため、こちらを使う。
@MainActor
func waitUntilOnMainActor(
    timeout: Duration = testTimeout(fallback: 10),
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(50))
    }
}

/// 条件が true になるまで action を定期的に実行しながらポーリングで待機する。
/// ファイル監視の再開が遅れた場合でも後続の書き込みで検知できるようにするリトライパターン。
/// 「単発アクション + waitUntil」ではイベントを取りこぼすと回復不能になるため、
/// 冪等な書き込み系アクションはこちらで発火するまで再試行する。
func waitUntilWithRetry(
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

/// `waitUntilWithRetry` の MainActor 版。`@Observable` ストアなど MainActor 隔離の
/// プロパティを条件・アクションから参照する場合に使う。
@MainActor
func waitUntilWithRetryOnMainActor(
    timeout: TimeInterval = 15,
    interval: TimeInterval = 0.5,
    action: () -> Void,
    until condition: () -> Bool
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
