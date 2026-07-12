@testable import befold
import Foundation
import Testing

private final class MockFetcher: ReleaseFetching, @unchecked Sendable {
    private let count = LockedBox(0)
    private let result: Result<GitHubRelease, Error>
    private let allResults: Result<[GitHubRelease], Error>?
    private let delayNanos: UInt64

    var callCount: Int {
        count.get()
    }

    init(
        result: Result<GitHubRelease, Error>,
        allResults: Result<[GitHubRelease], Error>? = nil,
        delayNanos: UInt64 = 0
    ) {
        self.result = result
        self.allResults = allResults
        self.delayNanos = delayNanos
    }

    func fetchLatest() async throws -> GitHubRelease {
        count.update { $0 += 1 }
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        return try result.get()
    }

    func fetchLatestIncludingPrerelease() async throws -> [GitHubRelease] {
        count.update { $0 += 1 }
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        return try (allResults ?? result.map { [$0] }).get()
    }
}

private struct DummyError: Error {}

private final class FakeClock: Sendable {
    private let time = LockedBox(Date(timeIntervalSince1970: 0))
    var current: Date {
        time.get()
    }

    func advance(by interval: TimeInterval) {
        time.update { $0 = $0.addingTimeInterval(interval) }
    }
}

private func makeRelease(tag: String) throws -> GitHubRelease {
    try GitHubRelease(
        tagName: tag,
        htmlURL: #require(URL(string: "https://github.com/YTommy109/befold/releases/tag/\(tag)")),
        assets: [
            GitHubRelease.Asset(
                name: "befold-\(tag).dmg",
                browserDownloadURL: #require(
                    URL(string: "https://github.com/YTommy109/befold/releases/download/\(tag)/befold-\(tag).dmg")
                )
            ),
        ]
    )
}

@Suite
@MainActor
struct UpdateCheckerTests {
    @Test(.timeLimit(.minutes(1)))
    func newerRemoteVersionIsReportedAsAvailable() async throws {
        let release = try makeRelease(tag: "v1.2.0")
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .success(release)), currentVersion: "1.1.1"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .updateAvailable(
            current: "1.1.1", latest: "v1.2.0", downloadURL: release.downloadURL
        ))
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["v1.1.1", "v1.0.0", "not-a-version"])
    func sameOlderOrUnparsableRemoteIsUpToDate(tag: String) async throws {
        let checker = try UpdateChecker(
            fetcher: MockFetcher(result: .success(makeRelease(tag: tag))),
            currentVersion: "1.1.1"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .upToDate(current: "1.1.1"))
    }

    @Test(.timeLimit(.minutes(1)))
    func unparsableCurrentVersionIsUpToDate() async throws {
        // 自バージョンがパースできない場合、リモートが新しくても更新扱いにしない
        let checker = try UpdateChecker(
            fetcher: MockFetcher(result: .success(makeRelease(tag: "v1.2.0"))),
            currentVersion: "not-a-version"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .upToDate(current: "not-a-version"))
    }

    @Test(.timeLimit(.minutes(1)))
    func newerReleaseWithoutDMGIsUpToDate() async throws {
        let release = try GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: #require(URL(string: "https://github.com/YTommy109/befold/releases/tag/v1.2.0")),
            assets: []
        )
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .success(release)), currentVersion: "1.1.1"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .upToDate(current: "1.1.1"))
    }

    @Test(.timeLimit(.minutes(1)))
    func fetchErrorReturnsFailed() async {
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .failure(DummyError())), currentVersion: "1.1.1"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .failed)
    }

    @Test(.timeLimit(.minutes(1)))
    func successfulResultIsCachedWithinTTL() async throws {
        let fetcher = try MockFetcher(result: .success(makeRelease(tag: "v1.2.0")))
        let clock = FakeClock()
        let checker = UpdateChecker(
            fetcher: fetcher, currentVersion: "1.1.1", now: { clock.current }
        )

        _ = await checker.check(bypassCache: false)
        clock.advance(by: 3599)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheExpiresAfterTTL() async throws {
        let fetcher = try MockFetcher(result: .success(makeRelease(tag: "v1.2.0")))
        let clock = FakeClock()
        let checker = UpdateChecker(
            fetcher: fetcher, currentVersion: "1.1.1", now: { clock.current }
        )

        _ = await checker.check(bypassCache: false)
        clock.advance(by: 3601)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func bypassCacheAlwaysFetches() async throws {
        let fetcher = try MockFetcher(result: .success(makeRelease(tag: "v1.2.0")))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        _ = await checker.check(bypassCache: false)
        _ = await checker.check(bypassCache: true)

        #expect(fetcher.callCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedResultIsNotCached() async {
        let fetcher = MockFetcher(result: .failure(DummyError()))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        _ = await checker.check(bypassCache: false)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentChecksShareOneFetch() async throws {
        let fetcher = try MockFetcher(
            result: .success(makeRelease(tag: "v1.2.0")), delayNanos: 50_000_000
        )
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        async let first = checker.check(bypassCache: false)
        async let second = checker.check(bypassCache: false)
        _ = await (first, second)

        #expect(fetcher.callCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func developChannelDetectsPrerelease() async throws {
        let devRelease = try makeRelease(tag: "v1.5.0-dev.1")
        let stableRelease = try makeRelease(tag: "v1.4.8")
        let checker = UpdateChecker(
            fetcher: MockFetcher(
                result: .success(stableRelease),
                allResults: .success([devRelease, stableRelease])
            ),
            currentVersion: "1.4.8",
            channel: .develop
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .updateAvailable(
            current: "1.4.8", latest: "v1.5.0-dev.1", downloadURL: devRelease.downloadURL
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func stableChannelIgnoresPrerelease() async throws {
        let stableRelease = try makeRelease(tag: "v1.4.8")
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .success(stableRelease)),
            currentVersion: "1.4.8"
        )

        let result = await checker.check(bypassCache: false)

        #expect(result == .upToDate(current: "1.4.8"))
    }
}
