import Foundation
import Testing

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

// 以下のポーリングヘルパーは、条件が成立しないままタイムアウトしたとき必ず
// `Issue.record` でテストを失敗させる。呼び出し側の `#expect` に頼らないのは、
// アサーションを書き忘れた箇所が「所定秒数を丸ごと浪費した上でグリーン」に
// なるのを防ぐため。戻り値は判定に使いたい場合のみ参照すればよい。

/// 条件が true になるまでポーリングで待機する。CI 環境でのファイル監視イベントや
/// タイマー発火の遅延に対応するため、固定 sleep ではなく条件成立を待つ。
/// - Returns: 条件が成立したら true。タイムアウトしたら失敗を記録して false。
@discardableResult
public func waitUntil(
    timeout: Duration = testTimeout(fallback: 10),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    if condition() { return true }
    Issue.record(
        "waitUntil が \(timeout) 以内に条件を満たさなかった", sourceLocation: sourceLocation
    )
    return false
}

/// `waitUntil` の MainActor 版。`@Observable` ストアなど MainActor 隔離のプロパティを
/// 参照する条件は Sendable クロージャにできないため、こちらを使う。
@MainActor
@discardableResult
public func waitUntilOnMainActor(
    timeout: Duration = testTimeout(fallback: 10),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    if condition() { return true }
    Issue.record(
        "waitUntilOnMainActor が \(timeout) 以内に条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}

/// 条件が true になるまで action を定期的に実行しながらポーリングで待機する。
/// ファイル監視の再開が遅れた場合でも後続の書き込みで検知できるようにするリトライパターン。
/// 「単発アクション + waitUntil」ではイベントを取りこぼすと回復不能になるため、
/// 冪等な書き込み系アクションはこちらで発火するまで再試行する。
/// - Returns: 条件が成立したら true。タイムアウトしたら失敗を記録して false。
@discardableResult
public func waitUntilWithRetry(
    timeout: TimeInterval = testTimeoutSeconds(fallback: 15),
    interval: TimeInterval = 0.5,
    sourceLocation: SourceLocation = #_sourceLocation,
    action: @escaping @Sendable () -> Void,
    until condition: @escaping @Sendable () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        action()
        let retryDeadline = Date().addingTimeInterval(interval)
        while !condition(), Date() < retryDeadline {
            try? await Task.sleep(for: .seconds(0.05))
        }
    }
    if condition() { return true }
    Issue.record(
        "waitUntilWithRetry が \(timeout) 秒以内に条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}

/// `waitUntilWithRetry` の MainActor 版。`@Observable` ストアなど MainActor 隔離の
/// プロパティを条件・アクションから参照する場合に使う。
@MainActor
@discardableResult
public func waitUntilWithRetryOnMainActor(
    timeout: TimeInterval = testTimeoutSeconds(fallback: 15),
    interval: TimeInterval = 0.5,
    sourceLocation: SourceLocation = #_sourceLocation,
    action: () -> Void,
    until condition: () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        action()
        let retryDeadline = Date().addingTimeInterval(interval)
        while !condition(), Date() < retryDeadline {
            try? await Task.sleep(for: .seconds(0.05))
        }
    }
    if condition() { return true }
    Issue.record(
        "waitUntilWithRetryOnMainActor が \(timeout) 秒以内に条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}
