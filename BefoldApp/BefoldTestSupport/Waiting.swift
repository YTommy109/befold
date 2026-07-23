import Foundation

/// ポーリング待機の既定タイムアウト秒数。`BEFOLD_TEST_TIMEOUT_SECONDS` が設定されていれば
/// それを秒数として使い、なければ `fallback` 秒を使う。ThreadSanitizer ジョブなど
/// スローダウンの大きい環境で CI 側からタイムアウトを延長できるようにする。
public func testTimeoutSeconds(fallback seconds: Double) -> Double {
    let raw = ProcessInfo.processInfo.environment["BEFOLD_TEST_TIMEOUT_SECONDS"]
    if let raw, let override = Double(raw) {
        return override
    }
    return seconds
}

public func testTimeout(fallback seconds: Double) -> Duration {
    .seconds(testTimeoutSeconds(fallback: seconds))
}

/// 条件が true になるまでポーリングで待機する。CI 環境でのファイル監視イベントや
/// タイマー発火の遅延に対応するため、固定 sleep ではなく条件成立を待つ。
public func waitUntil(
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
public func waitUntilOnMainActor(
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
public func waitUntilWithRetry(
    timeout: TimeInterval = testTimeoutSeconds(fallback: 15),
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
public func waitUntilWithRetryOnMainActor(
    timeout: TimeInterval = testTimeoutSeconds(fallback: 15),
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
