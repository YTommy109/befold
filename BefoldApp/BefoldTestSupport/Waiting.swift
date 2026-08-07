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

/// ポーリング予算より必ず長い `.timeLimit` を返す。
///
/// 両者を独立に書くとドリフトする。実際に thread-sanitizer ジョブでは
/// `BEFOLD_TEST_TIMEOUT_SECONDS: 120` へ延長した一方でスイート側は
/// `.timeLimit(.minutes(1))` のままだったため、**延長した予算を使い切る前に
/// テストが 60 秒で打ち切られる**という矛盾が起き、慢性的な赤の原因になっていた。
/// 同じ環境変数から導くことで、CI 側で予算を変えても打ち切りが自動的に追随する。
///
/// `.timeLimit` の粒度は分単位（切り上げ）のため、予算の 2 倍を分に換算して用いる。
public func testTimeLimit(pollingBudgetFallback seconds: Double = 15) -> TimeLimitTrait {
    let budget = testTimeoutSeconds(fallback: seconds)
    let minutes = max(1, Int((budget * 2 / 60).rounded(.up)))
    return .timeLimit(.minutes(minutes))
}

/// すべてのポーリングヘルパーが共有する内側ループ。条件が成立するか、`deadline` を
/// 過ぎるか、**タスクがキャンセルされる**まで 50ms 刻みで待つ。
///
/// キャンセルの扱いをここ 1 箇所に閉じるための共通化(TASK-340)。`try? await Task.sleep`
/// はキャンセル後に即時 throw を繰り返すため、ループ条件でキャンセルを見ないと
/// `.timeLimit` による打ち切り後もホットスピンし続ける(壁時計予算を持たない
/// `waitForMainActorDelivery` では永久に回り、CPU 100% のまま CI の
/// ジョブタイムアウトまで走る)。
///
/// `isolation:` の既定 `#isolation` で呼び出し元の隔離を引き継ぐ。`@MainActor` 版の
/// ヘルパーが渡す非 Sendable なクロージャも同じ実装で扱えるようにするため。
///
/// - Parameter deadline: 壁時計の期限。`nil` なら期限を持たない。
/// - Returns: 条件が成立したら true。期限切れ・キャンセルなら false。
private func pollUntil(
    deadline: ContinuousClock.Instant?,
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async -> Bool {
    while !condition() {
        if let deadline, ContinuousClock.now >= deadline { return false }
        if Task.isCancelled { return false }
        do {
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            return condition()
        }
    }
    return true
}

/// `action` を `interval` ごとに再実行しながら条件成立を待つ共通ループ。
/// 待機そのものは `pollUntil` に委ねるため、キャンセル対応はここにも自動的に効く。
///
/// - Parameter deadline: 壁時計の期限。`nil` なら期限を持たない。
/// - Returns: 条件が成立したら true。期限切れ・キャンセルなら false。
private func pollWithRetry(
    deadline: ContinuousClock.Instant?,
    interval: TimeInterval,
    isolation: isolated (any Actor)? = #isolation,
    action: () -> Void,
    until condition: () -> Bool
) async -> Bool {
    while !condition() {
        if let deadline, ContinuousClock.now >= deadline { return false }
        if Task.isCancelled { return false }
        action()
        var retryDeadline = ContinuousClock.now.advanced(by: .seconds(interval))
        if let deadline, deadline < retryDeadline { retryDeadline = deadline }
        if await pollUntil(deadline: retryDeadline, condition) { return true }
    }
    return true
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
    if await pollUntil(deadline: .now.advanced(by: timeout), condition) { return true }
    if condition() { return true }
    // キャンセルでの離脱は予算超過ではない(報告するとテスト打ち切りの巻き添えで
    // 無関係な失敗が増える)。呼び出し側は戻り値 false だけを受け取る。
    if Task.isCancelled { return false }
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
    if await pollUntil(deadline: .now.advanced(by: timeout), condition) { return true }
    if condition() { return true }
    // キャンセルでの離脱は予算超過ではない(報告するとテスト打ち切りの巻き添えで
    // 無関係な失敗が増える)。呼び出し側は戻り値 false だけを受け取る。
    if Task.isCancelled { return false }
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
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    if await pollWithRetry(deadline: deadline, interval: interval, action: action, until: condition) {
        return true
    }
    if condition() { return true }
    // キャンセルでの離脱は予算超過ではない(報告するとテスト打ち切りの巻き添えで
    // 無関係な失敗が増える)。呼び出し側は戻り値 false だけを受け取る。
    if Task.isCancelled { return false }
    Issue.record(
        "waitUntilWithRetry が \(timeout) 秒以内に条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}

/// `@MainActor` へホップして届くコールバックを、壁時計予算を持たずに待つ。
/// `action` を渡すと、条件が成立するまで `interval` ごとに再実行する
/// （`waitUntilWithRetry` と同じく、イベント取りこぼしを冪等な再試行で救済するため）。
///
/// 壁時計予算を持たないのは、full suite 実行では多数の `@MainActor` スイートが
/// メインアクターを占有し続け、メインアクターへの一巡そのものが待機予算を
/// 超えうるため。実測(TASK-335): FileWatcher の rename 判定は監視キュー上で
/// 即座に成立しているのに、`@MainActor` へホップしたコールバックが走るまで
/// 6 回中 6 回とも 10.6〜11.7 秒かかった(予算は 15 秒)。予算を延ばしても
/// 混雑の度合い次第で再発するため、**上限は持たずスイートの `.timeLimit` に
/// 委ねる**。こうすると混雑は遅延になるだけで失敗にはならない
/// （TASK-327 で ViewerWindowControllerToolbarTests に適用したのと同じ方針）。
///
/// 条件が本当に成立しない回帰では、この関数は条件成立を待ち続け、`.timeLimit` が
/// テストタスクをキャンセルした時点で戻る(共通ループ `pollWithRetry` がキャンセルを
/// 見るため、打ち切り後に `action` を回し続けることはない / TASK-340)。
/// 予算超過を `Issue.record` の 1 行で報告する `waitUntil` 系より診断は粗いので、
/// **`@MainActor` 配送を待つ箇所にだけ**使うこと。
public func waitForMainActorDelivery(
    interval: TimeInterval = 0.5,
    action: (@Sendable () -> Void)? = nil,
    until condition: @escaping @Sendable () -> Bool
) async {
    _ = await pollWithRetry(
        deadline: nil, interval: interval, action: { action?() }, until: condition
    )
}

/// `waitForMainActorDelivery` の `@MainActor` 版。`@Observable` ストアなど MainActor 隔離の
/// プロパティを条件から参照する場合に使う（`@Sendable` クロージャにできないため分けている。
/// `waitUntil` に対する `waitUntilOnMainActor` と同じ理由）。
///
/// 壁時計予算を持たない理由も既存版と同じ。加えて、swift-testing が報告する
/// テスト所要時間は「そのテスト自身の作業時間」ではなく**テスト開始からの壁時計**であり、
/// 全テストが一斉に開始されて `@MainActor` で直列化される full suite では、ほぼ全件が
/// 実行全体の長さを報告する（実測 TASK-354: TSan 付き全体実行 42.8 秒で 1367 件中 625 件が
/// 30 秒超を報告。await を 1 つも含まないテストも 38.5 秒と報告した）。
/// つまり待機に壁時計予算を持たせると、それは操作にかかった時間ではなく
/// **順番待ちの時間**を測ることになり、実行全体が長引くほど操作の成否と無関係に
/// 予算切れが起きる。上限はスイートの `.timeLimit` に委ねること。
@MainActor
public func waitForDeliveryOnMainActor(until condition: () -> Bool) async {
    _ = await pollUntil(deadline: nil, condition)
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
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    if await pollWithRetry(deadline: deadline, interval: interval, action: action, until: condition) {
        return true
    }
    if condition() { return true }
    // キャンセルでの離脱は予算超過ではない(報告するとテスト打ち切りの巻き添えで
    // 無関係な失敗が増える)。呼び出し側は戻り値 false だけを受け取る。
    if Task.isCancelled { return false }
    Issue.record(
        "waitUntilWithRetryOnMainActor が \(timeout) 秒以内に条件を満たさなかった",
        sourceLocation: sourceLocation
    )
    return false
}
