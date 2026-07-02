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

### Task 6: DMGMounter(hdiutil ラッパー + plist パース)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/DMGMounter.swift`
- Test: `MmdviewApp/mmdviewTests/DMGMounterTests.swift`

**Interfaces:**
- Produces: `struct DMGMounter: Sendable`
  - `func mount(dmgAt: URL) throws -> URL` / `func detach(mountPoint: URL)`
  - `static func mountPoint(fromPlist: Data) -> URL?`(純粋・テスト対象)

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Foundation
import Testing
@testable import mmdview

struct DMGMounterTests {
    @Test
    func extractsMountPointFromHdiutilPlist() throws {
        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>system-entities</key>
          <array>
            <dict>
              <key>content-hint</key>
              <string>GUID_partition_scheme</string>
            </dict>
            <dict>
              <key>content-hint</key>
              <string>Apple_HFS</string>
              <key>mount-point</key>
              <string>/Volumes/mmdview v1.2.0</string>
            </dict>
          </array>
        </dict>
        </plist>
        """.utf8)
        let mountPoint = DMGMounter.mountPoint(fromPlist: plist)
        #expect(mountPoint?.path == "/Volumes/mmdview v1.2.0")
    }

    @Test
    func returnsNilForPlistWithoutMountPoint() {
        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict><key>system-entities</key><array/></dict>
        </plist>
        """.utf8)
        #expect(DMGMounter.mountPoint(fromPlist: plist) == nil)
    }

    @Test
    func returnsNilForGarbageData() {
        #expect(DMGMounter.mountPoint(fromPlist: Data("not a plist".utf8)) == nil)
    }
}
```

- [ ] **Step 2: 失敗確認** — `swift test --filter DMGMounterTests` → コンパイルエラー

- [ ] **Step 3: 実装**

```swift
import Foundation

/// hdiutil を使った DMG のマウント/アンマウント(GUI 以外はテスト可能な純粋関数に分離)。
struct DMGMounter: Sendable {
    struct MountFailed: Error {}

    /// DMG をマウントしてマウントポイントを返す。
    /// Gatekeeper の警告を避けるため、事前に quarantine 属性を除去する。
    /// `Process` 実行でブロックするため、呼び出し側で `Task.detached` に載せること。
    func mount(dmgAt dmgURL: URL) throws -> URL {
        removeQuarantine(from: dmgURL)
        let output = try run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-plist"])
        guard let mountPoint = Self.mountPoint(fromPlist: output) else {
            throw MountFailed()
        }
        return mountPoint
    }

    func detach(mountPoint: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    /// `hdiutil attach -plist` の出力からマウントポイントを取り出す。
    static func mountPoint(fromPlist data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]]
        else {
            return nil
        }
        for entity in entities {
            if let path = entity["mount-point"] as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func removeQuarantine(from url: URL) {
        _ = try? run("/usr/bin/xattr", ["-d", "com.apple.quarantine", url.path])
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MountFailed()
        }
        return data
    }
}
```

- [ ] **Step 4: PASS 確認** — `swift test --filter DMGMounterTests`
- [ ] **Step 5: コミット(amend)** — `git add mmdview/Updates/DMGMounter.swift mmdviewTests/DMGMounterTests.swift && git commit --amend --no-edit`

---

### Task 7: UpdateInstaller(インストール純粋ロジック)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/UpdateInstaller.swift`
- Test: `MmdviewApp/mmdviewTests/UpdateInstallerTests.swift`

**Interfaces:**
- Produces: `enum UpdateInstaller`
  - `static func installedAppURL(bundleURL: URL) -> URL?`
  - `static func findApp(inMountPoint: URL) -> URL?`
  - `static func updaterScript(appInDMG: String, installedApp: String, mountPoint: String, dmgPath: String, pid: Int32) -> String`

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Foundation
import Testing
@testable import mmdview

struct UpdateInstallerTests {
    @Test
    func installedAppURLAcceptsAppBundle() {
        let bundle = URL(fileURLWithPath: "/Applications/mmdview.app")
        #expect(UpdateInstaller.installedAppURL(bundleURL: bundle) == bundle)
    }

    @Test
    func installedAppURLRejectsDevBuildDirectory() {
        let devDir = URL(fileURLWithPath: "/Users/dev/mmdview/.build/debug")
        #expect(UpdateInstaller.installedAppURL(bundleURL: devDir) == nil)
    }

    @Test
    func findsAppBundleInMountPoint() throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-installer-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mountPoint) }
        let app = mountPoint.appendingPathComponent("mmdview.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: mountPoint)?.lastPathComponent == "mmdview.app")
    }

    @Test
    func findAppReturnsNilForEmptyMountPoint() throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-installer-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mountPoint) }
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        #expect(UpdateInstaller.findApp(inMountPoint: mountPoint) == nil)
    }

    @Test
    func updaterScriptContainsAllSteps() {
        let script = UpdateInstaller.updaterScript(
            appInDMG: "/Volumes/mmdview v1.2.0/mmdview.app",
            installedApp: "/Applications/mmdview.app",
            mountPoint: "/Volumes/mmdview v1.2.0",
            dmgPath: "/tmp/mmdview-update.dmg",
            pid: 12345)

        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("kill -0 12345"))
        #expect(script.contains(#"rm -rf "/Applications/mmdview.app""#))
        #expect(script.contains(#"cp -R "/Volumes/mmdview v1.2.0/mmdview.app" "/Applications/mmdview.app""#))
        #expect(script.contains(#"hdiutil detach "/Volumes/mmdview v1.2.0" -force"#))
        #expect(script.contains(#"rm -f "/tmp/mmdview-update.dmg""#))
        #expect(script.contains(#"xattr -dr com.apple.quarantine "/Applications/mmdview.app""#))
        #expect(script.contains(#"open "/Applications/mmdview.app""#))
        #expect(script.contains(#"rm -f "$0""#))
    }
}
```

- [ ] **Step 2: 失敗確認** — `swift test --filter UpdateInstallerTests` → コンパイルエラー

- [ ] **Step 3: 実装**

```swift
import Foundation

/// ダウンロード済み DMG からアプリを差し替えるための純粋ロジック。
/// 実際のマウント・スクリプト起動は UpdateFlowController が行う。
enum UpdateInstaller {
    enum InstallError: Error {
        /// `.app` バンドル外(開発ビルド)から実行されている。
        case notInstalledApp
        /// DMG 内に `.app` が見つからない。
        case appNotFoundInDMG
    }

    /// 実行中バンドルが差し替え対象の `.app` なら、その URL を返す。
    static func installedAppURL(bundleURL: URL) -> URL? {
        bundleURL.pathExtension == "app" ? bundleURL : nil
    }

    /// マウントポイント直下の `.app` バンドルを探す。
    static func findApp(inMountPoint mountPoint: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    /// アプリ終了後に差し替え・再起動を行うシェルスクリプトを生成する。
    /// 元プロセスの終了は PID ポーリングで待つ。
    static func updaterScript(
        appInDMG: String,
        installedApp: String,
        mountPoint: String,
        dmgPath: String,
        pid: Int32
    ) -> String {
        """
        #!/bin/bash
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "\(installedApp)"
        /bin/cp -R "\(appInDMG)" "\(installedApp)"
        /usr/bin/hdiutil detach "\(mountPoint)" -force
        /bin/rm -f "\(dmgPath)"
        /usr/bin/xattr -dr com.apple.quarantine "\(installedApp)" 2>/dev/null
        /usr/bin/open "\(installedApp)"
        /bin/rm -f "$0"
        """
    }
}
```

- [ ] **Step 4: PASS 確認** — `swift test --filter UpdateInstallerTests`
- [ ] **Step 5: コミット(amend)**

---

### Task 8: UpdateDownloader(進捗付きダウンロード)

**Files:**
- Create: `MmdviewApp/mmdview/Updates/UpdateDownloader.swift`
- Test: `MmdviewApp/mmdviewTests/UpdateDownloaderTests.swift`

**Interfaces:**
- Produces: `struct UpdateDownloader: Sendable`
  - `func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws`

- [ ] **Step 1: 失敗するテストを書く**(`file://` URL で実ダウンロード)

```swift
import Foundation
import Testing
@testable import mmdview

struct UpdateDownloaderTests {
    @Test
    func downloadsFileAndReportsCompletion() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-download-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.bin")
        let content = Data((0..<200_000).map { UInt8($0 % 256) })
        try content.write(to: source)
        let destination = dir.appendingPathComponent("dest.bin")

        let recorder = ProgressRecorder()
        try await UpdateDownloader().download(from: source, to: destination) { value in
            recorder.record(value)
        }

        #expect(try Data(contentsOf: destination) == content)
        #expect(recorder.last == 1.0)
    }

    @Test
    func overwritesExistingDestination() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-download-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.bin")
        try Data("new".utf8).write(to: source)
        let destination = dir.appendingPathComponent("dest.bin")
        try Data("old-longer-content".utf8).write(to: destination)

        try await UpdateDownloader().download(from: source, to: destination) { _ in }

        #expect(try Data(contentsOf: destination) == Data("new".utf8))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var last: Double? { lock.withLock { values.last } }
    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }
}
```

- [ ] **Step 2: 失敗確認** — `swift test --filter UpdateDownloaderTests` → コンパイルエラー

- [ ] **Step 3: 実装**

```swift
import Foundation

/// DMG を指定先へストリーミングダウンロードする。
struct UpdateDownloader: Sendable {
    /// - Parameter progress: 0.0–1.0 の進捗(コンテンツ長が不明な場合は完了時のみ)。
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    progress(Double(written) / Double(expected))
                }
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1.0)
    }
}
```

- [ ] **Step 4: PASS 確認 + 全テスト** — `swift test`
- [ ] **Step 5: コミット(amend)**

---

### Task 9: UpdateFlowController + 進捗ウィンドウ + UpdateUI 再構成 + AppDelegate 接続

**Files:**
- Create: `MmdviewApp/mmdview/Updates/DownloadProgressWindow.swift`
- Create: `MmdviewApp/mmdview/Updates/UpdateFlowController.swift`
- Modify: `MmdviewApp/mmdview/Updates/UpdateUI.swift`(全面書き換え: ask 系 API に変更)
- Modify: `MmdviewApp/mmdview/App/AppDelegate.swift`(`runUpdateCheck` をフロー起動に変更)

**Interfaces:**
- Consumes: Task 6-8 の全 API、`UpdateCheckResult`(Task 3)
- Produces:
  - `@MainActor final class UpdateFlowController { var isRunning: Bool; func run(current:latest:downloadURL:) async }`
  - `UpdateUI.askInstall/askRelaunch/presentUpToDate/presentFailed/presentInstallFailed/presentDevBuildFallback`

- [ ] **Step 1: DownloadProgressWindow.swift**

```swift
import AppKit

/// ダウンロード進捗を表示する小ウィンドウ(GUI 層・自動テスト対象外)。
@MainActor
final class DownloadProgressWindowController: NSWindowController {
    private let indicator = NSProgressIndicator()

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.title = "アップデートをダウンロード中…"
        window.center()
        super.init(window: window)

        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.frame = NSRect(x: 20, y: 26, width: 280, height: 20)
        window.contentView?.addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setProgress(_ value: Double) {
        indicator.doubleValue = value
    }
}
```

- [ ] **Step 2: UpdateUI.swift を ask 系 API に書き換える**

```swift
import AppKit

/// 更新関連の NSAlert 表示(GUI 層・自動テスト対象外)。
@MainActor
enum UpdateUI {
    /// 「更新あり」の通知。true なら「ダウンロードしてインストール」が選ばれた。
    static func askInstall(current: String, latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "mmdview \(displayVersion(latest)) が利用可能です"
        alert.informativeText = "現在のバージョンは v\(current) です。ダウンロードしてインストールしますか?"
        alert.addButton(withTitle: "ダウンロードしてインストール")
        alert.addButton(withTitle: "後で")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// ダウンロード完了の確認。true なら「インストールして再起動」が選ばれた。
    static func askRelaunch(latest: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(displayVersion(latest)) のダウンロードが完了しました"
        alert.informativeText = "インストールするとアプリが再起動します。"
        alert.addButton(withTitle: "インストールして再起動")
        alert.addButton(withTitle: "後で")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 開発ビルドでは自動インストールできないため、ブラウザへフォールバックする。
    static func presentDevBuildFallback(downloadURL: URL) {
        presentInfo(message: "開発ビルドのため自動インストールできません。ダウンロードページを開きます。")
        NSWorkspace.shared.open(downloadURL)
    }

    static func presentUpToDate(current: String) {
        presentInfo(message: "最新バージョンです(v\(current))")
    }

    static func presentCheckFailed() {
        presentInfo(message: "アップデートの確認に失敗しました。")
    }

    static func presentInstallFailed() {
        presentInfo(message: "アップデートのインストールに失敗しました。")
    }

    private static func displayVersion(_ version: String) -> String {
        version.hasPrefix("v") ? version : "v\(version)"
    }

    private static func presentInfo(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
```

- [ ] **Step 3: UpdateFlowController.swift**

```swift
import AppKit

/// 「更新あり」以降のダウンロード→確認→インストールを担うフロー(GUI 層・自動テスト対象外)。
@MainActor
final class UpdateFlowController {
    private(set) var isRunning = false

    /// 更新フローを開始する。多重起動は無視する。
    func run(current: String, latest: String, downloadURL: URL) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        guard UpdateUI.askInstall(current: current, latest: latest) else { return }
        guard let installedApp = UpdateInstaller.installedAppURL(bundleURL: Bundle.main.bundleURL)
        else {
            UpdateUI.presentDevBuildFallback(downloadURL: downloadURL)
            return
        }

        let dmgURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-update.dmg")
        let progressWindow = DownloadProgressWindowController()
        progressWindow.showWindow(nil)
        do {
            try await UpdateDownloader().download(from: downloadURL, to: dmgURL) { value in
                Task { @MainActor in
                    progressWindow.setProgress(value)
                }
            }
            progressWindow.close()
            guard UpdateUI.askRelaunch(latest: latest) else { return }
            try await installAndRelaunch(dmgAt: dmgURL, installedApp: installedApp)
        } catch {
            progressWindow.close()
            UpdateUI.presentInstallFailed()
        }
    }

    /// DMG をマウントしてアップデータスクリプトを起動し、アプリを終了する。
    /// 成功時はプロセスが終了するため戻らない。
    private func installAndRelaunch(dmgAt dmgURL: URL, installedApp: URL) async throws {
        let mounter = DMGMounter()
        let mountPoint = try await Task.detached { try mounter.mount(dmgAt: dmgURL) }.value
        guard let appInDMG = UpdateInstaller.findApp(inMountPoint: mountPoint) else {
            await Task.detached { mounter.detach(mountPoint: mountPoint) }.value
            throw UpdateInstaller.InstallError.appNotFoundInDMG
        }

        let script = UpdateInstaller.updaterScript(
            appInDMG: appInDMG.path,
            installedApp: installedApp.path,
            mountPoint: mountPoint.path,
            dmgPath: dmgURL.path,
            pid: ProcessInfo.processInfo.processIdentifier)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmdview-updater.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()
        exit(0)
    }
}
```

- [ ] **Step 4: AppDelegate を接続する**

`updateChecker` プロパティの下に追加:

```swift
    private let updateFlow = UpdateFlowController()
```

`runUpdateCheck` を差し替え:

```swift
    /// 更新チェックを実行し、表示ポリシーに従って結果を提示する。
    /// 自動チェックは更新ありのときのみ、かつ同一バージョンはセッション中 1 回だけ表示する。
    private func runUpdateCheck(userInitiated: Bool) {
        Task {
            guard !updateFlow.isRunning else { return }
            let result = await updateChecker.check(bypassCache: userInitiated)
            switch result {
            case .updateAvailable(let current, let latest, let downloadURL):
                if !userInitiated, latest == announcedVersion { return }
                announcedVersion = latest
                await updateFlow.run(current: current, latest: latest, downloadURL: downloadURL)
            case .upToDate(let current):
                if userInitiated { UpdateUI.presentUpToDate(current: current) }
            case .failed:
                if userInitiated { UpdateUI.presentCheckFailed() }
            }
        }
    }
```

- [ ] **Step 5: ビルド・全テスト・起動確認** — `swift build && swift test`、
  `.build/debug/mmdview` を起動して更新アラート→「ダウンロードしてインストール」→
  開発ビルドフォールバック(ブラウザが開く)を確認
- [ ] **Step 6: xcodegen generate + コミット(amend)**

---

## 手動チェック項目(リリース前)

- [ ] メニュー「Check for Updates…」→ 最新なら「最新バージョンです」/新版があればインストール誘導
- [ ] 起動時に新版があればアラートが 1 回だけ出る(didBecomeActive との二重表示なし)
- [ ] アプリを一度非アクティブ→アクティブにしても同じバージョンの再通知が出ない
- [ ] About mmdview 表示時にもチェックが走る(1 時間キャッシュ内なら通信なし)
- [ ] ネットワーク遮断状態で手動チェック→「確認に失敗しました」、自動チェック→無反応
- [ ] 開発ビルド(`swift run`)で「ダウンロードしてインストール」→ フォールバックでブラウザが開く
- [ ] `/Applications` にインストールした旧バージョンで: ダウンロード進捗ウィンドウ →
      「インストールして再起動」→ アプリが新バージョンで再起動し、DMG と updater
      スクリプトが消えている
- [ ] インストール後の新アプリが quarantine なしで起動できる
