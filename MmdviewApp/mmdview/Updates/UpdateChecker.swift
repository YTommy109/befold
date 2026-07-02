import Foundation

/// 最新リリース情報の取得を抽象化する(テストではモックを注入する)。
protocol ReleaseFetching: Sendable {
    func fetchLatest() async throws -> GitHubRelease
}

/// 更新チェックの結果。
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, downloadURL: URL)
    case failed
}

/// GitHub Releases の最新バージョンと現在バージョンを比較する更新チェッカー。
/// 成功結果を TTL(既定 1 時間)キャッシュし、実行中のチェックには合流する。
@MainActor
final class UpdateChecker {
    private let fetcher: any ReleaseFetching
    private let currentVersion: String
    private let cacheTTL: TimeInterval
    private let now: () -> Date

    private var cached: (result: UpdateCheckResult, checkedAt: Date)?
    private var inFlight: Task<UpdateCheckResult, Never>?

    init(
        fetcher: any ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        cacheTTL: TimeInterval = 3600,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
        self.cacheTTL = cacheTTL
        self.now = now
    }

    /// 更新をチェックする。ネットワークエラー時も throw せず `.failed` を返す。
    /// - Parameter bypassCache: true(手動チェック)なら TTL キャッシュを無視して再取得する。
    func check(bypassCache: Bool) async -> UpdateCheckResult {
        if !bypassCache, let cached, now().timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached.result
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [fetcher, currentVersion] in
            await Self.performCheck(fetcher: fetcher, currentVersion: currentVersion)
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if result != .failed {
            cached = (result, now())
        }
        return result
    }

    private static func performCheck(
        fetcher: any ReleaseFetching, currentVersion: String
    ) async -> UpdateCheckResult {
        do {
            let release = try await fetcher.fetchLatest()
            guard let remote = AppVersion(release.tagName),
                  let current = AppVersion(currentVersion),
                  remote > current
            else {
                return .upToDate(current: currentVersion)
            }
            return .updateAvailable(
                current: currentVersion,
                latest: release.tagName,
                downloadURL: release.downloadURL)
        } catch {
            return .failed
        }
    }
}
