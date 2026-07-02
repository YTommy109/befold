# Check for Updates 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- derived-from ../specs/2026-07-02-check-for-updates-design.md -->

**Goal:** GitHub Releases API で新バージョンを検出し、メニュー実行時・起動時・アクティブ時・About 表示時に NSAlert で通知してブラウザ誘導する「Check for Updates…」機能を追加する。

**Architecture:** 純粋ロジック(バージョン比較・JSON デコード・TTL キャッシュ判定)を `MmdviewApp/mmdview/Updates/` に分離して Swift Testing で TDD。GUI 層(NSAlert・NSWorkspace)と AppDelegate 統合は自動テスト対象外(手動確認)。

**Tech Stack:** Swift 6 strict concurrency / URLSession async / Swift Testing / AppKit

## Global Constraints

- Swift 6 strict concurrency(`SWIFT_STRICT_CONCURRENCY: complete`)— 全型 `Sendable` 整合
- SwiftLint: line_length warning 120 / SwiftFormat 適用
- テストは Swift Testing(`@Suite` / `@Test` / `#expect`)、テスト名は英語 camelCase(既存踏襲)
- コミットは Conventional Commits + 日本語。**この機能のコード変更は 1 コミットに amend で集約する**(未 push のため)
- ビルド/テストは `cd MmdviewApp && swift build` / `swift test`
- GitHub API: `https://api.github.com/repos/YTommy109/mmdview/releases/latest`

---

### Task 1: AppVersion(バージョン比較)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/AppVersion.swift`
- Test: `MmdviewApp/mmdviewTests/AppVersionTests.swift`

**Interfaces:**
- Produces: `struct AppVersion: Comparable, Sendable`、`init?(_ string: String)`、`let components: [Int]`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import mmdview

struct AppVersionTests {
    @Test(arguments: [
        ("1.2.3", [1, 2, 3]),
        ("v1.2.3", [1, 2, 3]),
        ("0.1", [0, 1]),
        ("10.20.30", [10, 20, 30]),
    ])
    func parseValidVersion(input: String, expected: [Int]) {
        #expect(AppVersion(input)?.components == expected)
    }

    @Test(arguments: ["", "v", "abc", "1.2.beta", "1..2", "-1.2.3"])
    func parseInvalidVersionReturnsNil(input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test
    func compareVersions() throws {
        #expect(try #require(AppVersion("1.1.1")) < #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("1.2")) < #require(AppVersion("1.2.1")))
        #expect(try #require(AppVersion("v2.0.0")) > #require(AppVersion("1.9.9")))
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.0")))
    }

    @Test
    func equalityPadsMissingComponents() throws {
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter AppVersionTests`
Expected: コンパイルエラー(`AppVersion` 未定義)

- [ ] **Step 3: 最小実装を書く**

```swift
/// セマンティックバージョン("1.2.3" / "v1.2.3")のパースと比較。
/// 桁数が異なる場合は 0 埋めで比較する(1.2 == 1.2.0、1.2 < 1.2.1)。
struct AppVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var body = string
        if body.hasPrefix("v") {
            body.removeFirst()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
```

注意: `Int("-1")` は成功するため `value >= 0` ガードが必要。`"1..2"` は空要素で nil。

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter AppVersionTests`
Expected: PASS(全ケース)

- [ ] **Step 5: コミット**

```bash
git add MmdviewApp/mmdview/Updates/AppVersion.swift MmdviewApp/mmdviewTests/AppVersionTests.swift
git commit -m "feat: Check for Updates メニューを追加する"
```

---

### Task 2: GitHubRelease(API レスポンスのデコード)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/GitHubRelease.swift`
- Test: `MmdviewApp/mmdviewTests/GitHubReleaseTests.swift`

**Interfaces:**
- Produces: `struct GitHubRelease: Decodable, Equatable, Sendable`
  - `let tagName: String` / `let htmlURL: URL` / `let assets: [Asset]`
  - `struct Asset: Decodable, Equatable, Sendable { let name: String; let browserDownloadURL: URL }`
  - `var downloadURL: URL`(`.dmg` アセット優先、なければ `htmlURL`)
  - メンバワイズ init はテスト・Task 3 のモックで使用する

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Foundation
import Testing
@testable import mmdview

struct GitHubReleaseTests {
    private let apiJSON = Data("""
    {
      "tag_name": "v1.2.0",
      "html_url": "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0",
      "assets": [
        {
          "name": "mmdview-v1.2.0.dmg",
          "browser_download_url": "https://github.com/YTommy109/mmdview/releases/download/v1.2.0/mmdview-v1.2.0.dmg"
        }
      ]
    }
    """.utf8)

    @Test
    func decodeLatestReleaseResponse() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.tagName == "v1.2.0")
        #expect(release.htmlURL.absoluteString == "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "mmdview-v1.2.0.dmg")
    }

    @Test
    func downloadURLPrefersDmgAsset() throws {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: apiJSON)
        #expect(release.downloadURL.absoluteString.hasSuffix("mmdview-v1.2.0.dmg"))
    }

    @Test
    func downloadURLFallsBackToReleasePage() throws {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: try #require(URL(string: "https://github.com/YTommy109/mmdview/releases/tag/v1.2.0")),
            assets: [])
        #expect(release.downloadURL == release.htmlURL)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter GitHubReleaseTests`
Expected: コンパイルエラー(`GitHubRelease` 未定義)

- [ ] **Step 3: 最小実装を書く**

```swift
import Foundation

/// GitHub Releases API(`releases/latest`)のレスポンス。
struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    /// `.dmg` アセットの URL。なければリリースページにフォールバックする。
    var downloadURL: URL {
        assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter GitHubReleaseTests`
Expected: PASS

- [ ] **Step 5: コミット(amend)**

```bash
git add MmdviewApp/mmdview/Updates/GitHubRelease.swift MmdviewApp/mmdviewTests/GitHubReleaseTests.swift
git commit --amend --no-edit
```

---

### Task 3: ReleaseFetching + UpdateChecker(判定・TTL・合流)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/UpdateChecker.swift`(`ReleaseFetching` / `UpdateCheckResult` / `UpdateChecker`)
- Test: `MmdviewApp/mmdviewTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `AppVersion`(Task 1)、`GitHubRelease`(Task 2、メンバワイズ init)
- Produces:
  - `protocol ReleaseFetching: Sendable { func fetchLatest() async throws -> GitHubRelease }`
  - `enum UpdateCheckResult: Equatable, Sendable { case upToDate(current: String); case updateAvailable(current: String, latest: String, downloadURL: URL); case failed }`
  - `@MainActor final class UpdateChecker` /
    `init(fetcher: any ReleaseFetching, currentVersion: String, cacheTTL: TimeInterval = 3600, now: @escaping () -> Date = Date.init)` /
    `func check(bypassCache: Bool) async -> UpdateCheckResult`

- [ ] **Step 1: 失敗するテストを書く**

```swift
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
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `cd MmdviewApp && swift test --filter UpdateCheckerTests`
Expected: コンパイルエラー(`ReleaseFetching` / `UpdateChecker` 未定義)

- [ ] **Step 3: 最小実装を書く**

```swift
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
```

注意: この時点では `GitHubReleaseFetcher`(Task 4)が未定義なので、デフォルト引数
`= GitHubReleaseFetcher()` は **Task 4 で追加** し、Task 3 では
`init(fetcher: any ReleaseFetching, ...)`(デフォルトなし)にしておく。

- [ ] **Step 4: テストが通ることを確認する**

Run: `cd MmdviewApp && swift test --filter UpdateCheckerTests`
Expected: PASS(9 ケース)

- [ ] **Step 5: 全テスト実行 + コミット(amend)**

Run: `cd MmdviewApp && swift test`
Expected: 既存含め全 PASS

```bash
git add MmdviewApp/mmdview/Updates/UpdateChecker.swift MmdviewApp/mmdviewTests/UpdateCheckerTests.swift
git commit --amend --no-edit
```

---

### Task 4: GitHubReleaseFetcher + UpdateUI(GUI 層)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/ReleaseFetcher.swift`
- Create: `MmdviewApp/mmdview/Updates/UpdateUI.swift`
- Modify: `MmdviewApp/mmdview/Updates/UpdateChecker.swift`(init に `= GitHubReleaseFetcher()` デフォルトを追加)

**Interfaces:**
- Consumes: `ReleaseFetching` / `UpdateCheckResult`(Task 3)、`GitHubRelease`(Task 2)
- Produces:
  - `struct GitHubReleaseFetcher: ReleaseFetching`
  - `@MainActor enum UpdateUI { static func present(_ result: UpdateCheckResult, userInitiated: Bool) }`

ネットワークと NSAlert は自動テスト対象外(テスト規約どおり GUI 層はリリース前手動チェック)。

- [ ] **Step 1: ReleaseFetcher.swift を書く**

```swift
import Foundation

/// GitHub Releases API から最新リリースを取得する。
struct GitHubReleaseFetcher: ReleaseFetching {
    private static let endpoint =
        "https://api.github.com/repos/YTommy109/mmdview/releases/latest"

    func fetchLatest() async throws -> GitHubRelease {
        guard let url = URL(string: Self.endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
```

- [ ] **Step 2: UpdateUI.swift を書く**

```swift
import AppKit

/// 更新チェック結果を NSAlert でユーザーに提示する(GUI 層・自動テスト対象外)。
@MainActor
enum UpdateUI {
    /// - Parameter userInitiated: 手動チェックなら「最新」「失敗」も表示する。
    static func present(_ result: UpdateCheckResult, userInitiated: Bool) {
        switch result {
        case .updateAvailable(let current, let latest, let downloadURL):
            presentUpdateAvailable(current: current, latest: latest, downloadURL: downloadURL)
        case .upToDate(let current):
            guard userInitiated else { return }
            presentInfo(message: "最新バージョンです(v\(current))")
        case .failed:
            guard userInitiated else { return }
            presentInfo(message: "アップデートの確認に失敗しました。")
        }
    }

    private static func presentUpdateAvailable(current: String, latest: String, downloadURL: URL) {
        let displayLatest = latest.hasPrefix("v") ? latest : "v\(latest)"
        let alert = NSAlert()
        alert.messageText = "mmdview \(displayLatest) が利用可能です"
        alert.informativeText = "現在のバージョンは v\(current) です。ダウンロードページを開きますか?"
        alert.addButton(withTitle: "ダウンロード")
        alert.addButton(withTitle: "後で")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
```

- [ ] **Step 3: UpdateChecker の init にデフォルト fetcher を追加する**

`UpdateChecker.swift` の `init(fetcher: any ReleaseFetching,` を
`init(fetcher: any ReleaseFetching = GitHubReleaseFetcher(),` に変更。

- [ ] **Step 4: ビルドと全テストを確認する**

Run: `cd MmdviewApp && swift build && swift test`
Expected: ビルド成功・全 PASS

- [ ] **Step 5: コミット(amend)**

```bash
git add MmdviewApp/mmdview/Updates/ReleaseFetcher.swift MmdviewApp/mmdview/Updates/UpdateUI.swift MmdviewApp/mmdview/Updates/UpdateChecker.swift
git commit --amend --no-edit
```

---

### Task 5: メニューと AppDelegate 統合

**Files:**
- Modify: `MmdviewApp/mmdview/App/MainMenuBuilder.swift:17-21`(About のアクション変更 + Check for Updates… 追加)
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift`(checker 保持・トリガー 4 つ・表示ポリシー)

**Interfaces:**
- Consumes: `UpdateChecker.check(bypassCache:)` / `UpdateUI.present(_:userInitiated:)` / `UpdateCheckResult`
- Produces: `@objc func checkForUpdates(_ sender: Any?)` / `@objc func showAbout(_ sender: Any?)`(メニューからレスポンダチェーン経由で呼ばれる)

- [ ] **Step 1: MainMenuBuilder の App メニュー先頭を差し替える**

`makeAppMenuItem()` の About 項目(17-21 行目)を以下に変更:

```swift
        menu.addItem(
            withTitle: "About mmdview",
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: "")
        menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
```

(既存項目同様 target は設定しない。レスポンダチェーン末尾の AppDelegate に届く)

- [ ] **Step 2: AppDelegate に更新チェックを組み込む**

プロパティ追加(`windowControllers` の下):

```swift
    private let updateChecker = UpdateChecker()
    /// 自動チェックで通知済みの最新バージョン(セッション中の再通知を抑止する)。
    private var announcedVersion: String?
```

`applicationDidFinishLaunching` の末尾に追加:

```swift
        runUpdateCheck(userInitiated: false)
```

`applicationShouldHandleReopen` の下にライフサイクルフック追加:

```swift
    func applicationDidBecomeActive(_ notification: Notification) {
        runUpdateCheck(userInitiated: false)
    }
```

`showOpenPanel` の下にアクションとヘルパーを追加(`// MARK: - Update Check` セクション):

```swift
    // MARK: - Update Check

    /// About パネルを表示し、あわせて更新を自動チェックする。
    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        runUpdateCheck(userInitiated: false)
    }

    /// メニューの「Check for Updates…」。キャッシュを無視して確認し、結果を必ず表示する。
    @objc func checkForUpdates(_ sender: Any?) {
        runUpdateCheck(userInitiated: true)
    }

    /// 更新チェックを実行し、表示ポリシーに従って結果を提示する。
    /// 自動チェックは更新ありのときのみ、かつ同一バージョンはセッション中 1 回だけ表示する。
    private func runUpdateCheck(userInitiated: Bool) {
        Task {
            let result = await updateChecker.check(bypassCache: userInitiated)
            if case .updateAvailable(_, let latest, _) = result {
                if !userInitiated, latest == announcedVersion {
                    return
                }
                announcedVersion = latest
            }
            UpdateUI.present(result, userInitiated: userInitiated)
        }
    }
```

- [ ] **Step 3: ビルドと全テストを確認する**

Run: `cd MmdviewApp && swift build && swift test`
Expected: ビルド成功・全 PASS

- [ ] **Step 4: 動作確認(起動)**

Run: `cd MmdviewApp && swift run mmdview` を数秒起動(または /run スキル相当)して
メニューに「Check for Updates…」が出ること、起動がクラッシュしないことを確認。
SPM 実行では `CFBundleShortVersionString` がなく currentVersion "0" となり
「更新あり」アラートが出るのは想定どおり(判定ロジックが本物の API で動いている証拠)。

- [ ] **Step 5: コミット(amend)+ xcodegen 確認**

```bash
cd MmdviewApp && xcodegen generate   # Updates/ が Xcode プロジェクトに入ることを確認
git add MmdviewApp/mmdview/App/MainMenuBuilder.swift MmdviewApp/mmdview/App/AppDelegate.swift MmdviewApp/mmdview.xcodeproj
git commit --amend --no-edit
```

---

## 手動チェック項目(リリース前)

- [ ] メニュー「Check for Updates…」→ 最新なら「最新バージョンです」/新版があればダウンロード誘導
- [ ] 「ダウンロード」ボタンでブラウザが DMG URL を開く
- [ ] 起動時に新版があればアラートが 1 回だけ出る(didBecomeActive との二重表示なし)
- [ ] アプリを一度非アクティブ→アクティブにしても同じバージョンの再通知が出ない
- [ ] About mmdview 表示時にもチェックが走る(1 時間キャッシュ内なら通信なし)
- [ ] ネットワーク遮断状態で手動チェック→「確認に失敗しました」、自動チェック→無反応
