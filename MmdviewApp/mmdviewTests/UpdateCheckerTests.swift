import Foundation
import Testing
@testable import mmdview

private final class MockFetcher: ReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let result: Result<GitHubRelease, Error>
    private let delayNanos: UInt64

    var callCount: Int { lock.withLock { count } }

    init(result: Result<GitHubRelease, Error>, delayNanos: UInt64 = 0) {
        self.result = result
        self.delayNanos = delayNanos
    }

    func fetchLatest() async throws -> GitHubRelease {
        lock.withLock { count += 1 }
        if delayNanos > 0 {
            try await Task.sleep(nanoseconds: delayNanos)
        }
        return try result.get()
    }
}

private struct DummyError: Error {}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 0)
    var current: Date { lock.withLock { time } }
    func advance(by interval: TimeInterval) {
        lock.withLock { time = time.addingTimeInterval(interval) }
    }
}

private func makeRelease(tag: String) throws -> GitHubRelease {
    GitHubRelease(
        tagName: tag,
        htmlURL: try #require(URL(string: "https://github.com/YTommy109/mmdview/releases/tag/\(tag)")),
        assets: [
            GitHubRelease.Asset(
                name: "mmdview-\(tag).dmg",
                browserDownloadURL: try #require(
                    URL(string: "https://github.com/YTommy109/mmdview/releases/download/\(tag)/mmdview-\(tag).dmg"))),
        ])
}

@Suite
@MainActor
struct UpdateCheckerTests {
    @Test
    func newerRemoteVersionIsReportedAsAvailable() async throws {
        let release = try makeRelease(tag: "v1.2.0")
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .success(release)), currentVersion: "1.1.1")

        let result = await checker.check(bypassCache: false)

        #expect(result == .updateAvailable(
            current: "1.1.1", latest: "v1.2.0", downloadURL: release.downloadURL))
    }

    @Test(arguments: ["v1.1.1", "v1.0.0", "not-a-version"])
    func sameOlderOrUnparsableRemoteIsUpToDate(tag: String) async throws {
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .success(try makeRelease(tag: tag))),
            currentVersion: "1.1.1")

        let result = await checker.check(bypassCache: false)

        #expect(result == .upToDate(current: "1.1.1"))
    }

    @Test
    func fetchErrorReturnsFailed() async {
        let checker = UpdateChecker(
            fetcher: MockFetcher(result: .failure(DummyError())), currentVersion: "1.1.1")

        let result = await checker.check(bypassCache: false)

        #expect(result == .failed)
    }

    @Test
    func successfulResultIsCachedWithinTTL() async throws {
        let fetcher = MockFetcher(result: .success(try makeRelease(tag: "v1.2.0")))
        let clock = FakeClock()
        let checker = UpdateChecker(
            fetcher: fetcher, currentVersion: "1.1.1", now: { clock.current })

        _ = await checker.check(bypassCache: false)
        clock.advance(by: 3599)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 1)
    }

    @Test
    func cacheExpiresAfterTTL() async throws {
        let fetcher = MockFetcher(result: .success(try makeRelease(tag: "v1.2.0")))
        let clock = FakeClock()
        let checker = UpdateChecker(
            fetcher: fetcher, currentVersion: "1.1.1", now: { clock.current })

        _ = await checker.check(bypassCache: false)
        clock.advance(by: 3601)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 2)
    }

    @Test
    func bypassCacheAlwaysFetches() async throws {
        let fetcher = MockFetcher(result: .success(try makeRelease(tag: "v1.2.0")))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        _ = await checker.check(bypassCache: false)
        _ = await checker.check(bypassCache: true)

        #expect(fetcher.callCount == 2)
    }

    @Test
    func failedResultIsNotCached() async {
        let fetcher = MockFetcher(result: .failure(DummyError()))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        _ = await checker.check(bypassCache: false)
        _ = await checker.check(bypassCache: false)

        #expect(fetcher.callCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentChecksShareOneFetch() async throws {
        let fetcher = MockFetcher(
            result: .success(try makeRelease(tag: "v1.2.0")), delayNanos: 50_000_000)
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.1")

        async let first = checker.check(bypassCache: false)
        async let second = checker.check(bypassCache: false)
        _ = await (first, second)

        #expect(fetcher.callCount == 1)
    }
}
