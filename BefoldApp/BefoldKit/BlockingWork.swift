import Foundation

/// 協調スレッドプールの外で `work` を実行し、結果を待つ。
///
/// `Task.detached` は協調スレッドプールの上で走るため、subprocess の待ちや
/// ファイル I/O のように**同期的に長く塞ぐ**処理を置いてはならない。プールの幅は
/// コア数で固定されており、幅ぶんの同時ブロックでプロセス全体の前進が止まる
/// (TASK-424 / TASK-427 / TASK-516 で 3 度再発した)。
///
/// 専用スレッドを 1 回の呼び出しにつき 1 本立てる。`DispatchQueue` の並行キューは
/// 使えない——libdispatch の非 overcommit なワーカープールもコア数で頭打ちになるため、
/// 塞ぐ処理を並べると同じ枯渇が起きる(実測: 並行キュー実装では全件実行で
/// `ViewerWindowManagerRecentRepositoriesTests` の 6 テストが待機上限に達した)。
/// スレッド生成のコスト(数十マイクロ秒)は、ここに置く処理(subprocess 起動・stat・
/// ファイル読み込み)のコストに対して無視できる。
public func withBlockingWork<T: Sendable>(
    qos: DispatchQoS = .utility,
    _ work: @escaping @Sendable () -> T
) async -> T {
    await withCheckedContinuation { continuation in
        let thread = Thread { continuation.resume(returning: work()) }
        thread.qualityOfService = qos.qosClass.qualityOfService
        thread.start()
    }
}

private extension DispatchQoS.QoSClass {
    var qualityOfService: QualityOfService {
        switch self {
        case .userInteractive: .userInteractive
        case .userInitiated: .userInitiated
        case .utility: .utility
        case .background: .background
        case .default, .unspecified: .default
        @unknown default: .default
        }
    }
}
