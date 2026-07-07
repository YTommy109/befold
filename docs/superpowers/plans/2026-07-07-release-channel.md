# リリースチャンネル機能 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** stable/develop の 2 チャンネルを導入し、開発者が `defaults` コマンドで develop に切り替えると pre-release の更新通知も受け取れるようにする。

**Architecture:** `AppVersion` にプレリリース識別子パース・比較を追加し、`UpdateChannel` enum で UserDefaults からチャンネルを読み取り、`ReleaseFetcher` に `/releases` 一覧取得メソッドを追加して `UpdateChecker` がチャンネルに応じて使い分ける。`bump.sh` と `/release` スキルに `dev` 引数を追加し、プレリリースタグを生成する。

**Tech Stack:** Swift 6 / Swift Testing / Bash

## Global Constraints

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- macOS 14+
- テストフレームワーク: Swift Testing（`@Test`, `#expect`）
- テスト関数名は英語 camelCase、日本語説明は `@Test("日本語")` で
- Conventional Commits + 日本語コミットメッセージ
- CI の `prerelease:` フラグと `GitHubRelease.hasDMG` / `UpdateChecker` の DMG チェックは対応済み

---

### Task 1: `AppVersion` のプレリリース対応

**Files:**
- Modify: `BefoldApp/befold/Updates/AppVersion.swift`
- Test: `BefoldApp/befoldTests/AppVersionTests.swift`

**Interfaces:**
- Produces: `AppVersion.components: [Int]`（既存）, `AppVersion.prerelease: [String]?`（新規）
  - `prerelease` は `nil`（正式版）または `["dev", "1"]` 等の文字列配列
  - 比較: 正式版 > プレリリース版、プレリリース同士はドット区切りを数値優先で順に比較（SemVer 準拠）

- [ ] **Step 1: プレリリース版のパーステストを書く**

`BefoldApp/befoldTests/AppVersionTests.swift` に以下を追加:

```swift
@Test(arguments: [
    ("1.5.0-dev.1", [1, 5, 0], ["dev", "1"]),
    ("v2.0.0-beta.3", [2, 0, 0], ["beta", "3"]),
    ("1.0.0-alpha", [1, 0, 0], ["alpha"]),
])
func parsePrereleaseVersion(input: String, expectedComponents: [Int], expectedPrerelease: [String]) {
    let version = AppVersion(input)
    #expect(version?.components == expectedComponents)
    #expect(version?.prerelease == expectedPrerelease)
}

@Test
func stableVersionHasNilPrerelease() {
    #expect(AppVersion("1.2.3")?.prerelease == nil)
}
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `cd BefoldApp && swift test --filter AppVersionTests 2>&1 | tail -20`
Expected: コンパイルエラー（`prerelease` プロパティが存在しない）

- [ ] **Step 3: `AppVersion` にプレリリースパースを実装**

`BefoldApp/befold/Updates/AppVersion.swift` を以下に書き換える:

```swift
/// セマンティックバージョン("1.2.3" / "v1.2.3" / "1.2.3-dev.1")のパースと比較。
/// 桁数が異なる場合は 0 埋めで比較する(1.2 == 1.2.0、1.2 < 1.2.1)。
/// プレリリース識別子は SemVer 準拠: 正式版 > プレリリース版。
struct AppVersion: Comparable, Sendable {
    let components: [Int]
    let prerelease: [String]?

    init?(_ string: String) {
        var body = string
        if body.hasPrefix("v") {
            body.removeFirst()
        }
        let prereleaseStart = body.firstIndex(of: "-")
        let versionPart = prereleaseStart.map { body[body.startIndex ..< $0] }
            ?? body[body.startIndex...]
        let parts = versionPart.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed

        if let start = prereleaseStart {
            let suffix = body[body.index(after: start)...]
            guard !suffix.isEmpty else { return nil }
            prerelease = suffix.split(separator: ".").map(String.init)
        } else {
            prerelease = nil
        }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        // 同じ数値部分: 正式版 > プレリリース版
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false   // lhs は正式版、rhs はプレリリース → lhs > rhs
        case (_, nil): return true    // lhs はプレリリース、rhs は正式版 → lhs < rhs
        case let (lp?, rp?):
            let preCount = max(lp.count, rp.count)
            for index in 0 ..< preCount {
                guard index < lp.count else { return true }
                guard index < rp.count else { return false }
                if let li = Int(lp[index]), let ri = Int(rp[index]) {
                    if li != ri { return li < ri }
                } else {
                    if lp[index] != rp[index] { return lp[index] < rp[index] }
                }
            }
            return false
        }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
```

- [ ] **Step 4: テスト実行でパーステストの通過を確認**

Run: `cd BefoldApp && swift test --filter AppVersionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: プレリリース版の比較テストを書く**

`BefoldApp/befoldTests/AppVersionTests.swift` に以下を追加:

```swift
@Test(arguments: [
    ("1.5.0-dev.1", "1.5.0"),      // プレリリース < 正式版
    ("1.5.0-dev.1", "1.5.0-dev.2"), // dev.1 < dev.2
    ("1.5.0-alpha", "1.5.0-beta"),  // alpha < beta（文字列比較）
    ("1.4.9", "1.5.0-dev.1"),       // 数値部分が小さい < プレリリース
])
func comparePrereleaseVersions(lower: String, higher: String) throws {
    #expect(try #require(AppVersion(lower)) < #require(AppVersion(higher)))
}

@Test
func prereleaseWithSameIdentifiersAreEqual() throws {
    #expect(try #require(AppVersion("1.5.0-dev.1")) == #require(AppVersion("v1.5.0-dev.1")))
}
```

- [ ] **Step 6: テスト実行で通過を確認**

Run: `cd BefoldApp && swift test --filter AppVersionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/Updates/AppVersion.swift BefoldApp/befoldTests/AppVersionTests.swift
git commit -m "feat: AppVersion にプレリリース識別子のパースと比較を追加する"
```

---

### Task 2: `UpdateChannel` enum と `ReleaseFetcher` の拡張

**Files:**
- Create: `BefoldApp/befold/Updates/UpdateChannel.swift`
- Modify: `BefoldApp/befold/Updates/UpdateChecker.swift`
- Modify: `BefoldApp/befold/Updates/ReleaseFetcher.swift`
- Test: `BefoldApp/befoldTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `AppVersion` with `prerelease` support (Task 1), `GitHubRelease.hasDMG` (already done)
- Produces:
  - `UpdateChannel` enum: `.stable`, `.develop`; `UpdateChannel.current` reads from UserDefaults
  - `ReleaseFetching.fetchLatestIncludingPrerelease() async throws -> GitHubRelease`
  - `UpdateChecker.init(fetcher:currentVersion:channel:cacheTTL:now:)`

- [ ] **Step 1: `UpdateChannel` のテストを書く**

`BefoldApp/befoldTests/UpdateCheckerTests.swift` に以下を追加:

```swift
@Suite
struct UpdateChannelTests {
    @Test
    func defaultChannelIsStable() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        #expect(UpdateChannel.read(from: defaults) == .stable)
    }

    @Test
    func developChannelIsReadFromDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        defaults.set("develop", forKey: "UpdateChannel")
        #expect(UpdateChannel.read(from: defaults) == .develop)
    }

    @Test
    func unknownValueFallsBackToStable() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        defaults.set("unknown", forKey: "UpdateChannel")
        #expect(UpdateChannel.read(from: defaults) == .stable)
    }
}
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `cd BefoldApp && swift test --filter UpdateChannelTests 2>&1 | tail -20`
Expected: コンパイルエラー（`UpdateChannel` が存在しない）

- [ ] **Step 3: `UpdateChannel` enum を作成**

`BefoldApp/befold/Updates/UpdateChannel.swift`:

```swift
import Foundation

enum UpdateChannel: String, Sendable {
    case stable
    case develop

    static func read(from defaults: UserDefaults = .standard) -> UpdateChannel {
        defaults.string(forKey: "UpdateChannel")
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }
}
```

- [ ] **Step 4: テスト実行で通過を確認**

Run: `cd BefoldApp && swift test --filter UpdateChannelTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: develop チャンネルの更新チェックテストを書く**

`BefoldApp/befoldTests/UpdateCheckerTests.swift` の `MockFetcher` に `fetchLatestIncludingPrerelease` を追加し、develop チャンネルのテストを書く。

まず `MockFetcher` を更新:

```swift
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
```

次に develop チャンネルのテストを追加:

```swift
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
```

- [ ] **Step 6: テスト実行で失敗を確認**

Run: `cd BefoldApp && swift test --filter UpdateCheckerTests 2>&1 | tail -20`
Expected: コンパイルエラー（`channel` パラメータ、`fetchLatestIncludingPrerelease` が存在しない）

- [ ] **Step 7: `ReleaseFetching` プロトコルと `GitHubReleaseFetcher` を拡張**

`BefoldApp/befold/Updates/UpdateChecker.swift` のプロトコルを更新:

```swift
protocol ReleaseFetching: Sendable {
    func fetchLatest() async throws -> GitHubRelease
    func fetchLatestIncludingPrerelease() async throws -> [GitHubRelease]
}
```

`BefoldApp/befold/Updates/ReleaseFetcher.swift` を更新:

```swift
import Foundation

struct GitHubReleaseFetcher: ReleaseFetching {
    private static let latestEndpoint =
        "https://api.github.com/repos/YTommy109/befold/releases/latest"
    private static let allEndpoint =
        "https://api.github.com/repos/YTommy109/befold/releases?per_page=10"

    func fetchLatest() async throws -> GitHubRelease {
        let data = try await fetch(Self.latestEndpoint)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func fetchLatestIncludingPrerelease() async throws -> [GitHubRelease] {
        let data = try await fetch(Self.allEndpoint)
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func fetch(_ endpoint: String) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try response.validateHTTPSuccess()
        return data
    }
}
```

- [ ] **Step 8: `UpdateChecker` にチャンネル対応を追加**

`BefoldApp/befold/Updates/UpdateChecker.swift` の `UpdateChecker` を更新:

```swift
@MainActor
final class UpdateChecker {
    private let fetcher: any ReleaseFetching
    private let currentVersion: String
    private let channel: UpdateChannel
    private let cacheTTL: TimeInterval
    private let now: () -> Date

    private var cached: (result: UpdateCheckResult, checkedAt: Date)?
    private var inFlight: Task<UpdateCheckResult, Never>?

    init(
        fetcher: any ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        channel: UpdateChannel = .read(),
        cacheTTL: TimeInterval = 3600,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
        self.channel = channel
        self.cacheTTL = cacheTTL
        self.now = now
    }

    func check(bypassCache: Bool) async -> UpdateCheckResult {
        if !bypassCache, let cached, now().timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached.result
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [fetcher, currentVersion, channel] in
            await Self.performCheck(fetcher: fetcher, currentVersion: currentVersion, channel: channel)
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
        fetcher: any ReleaseFetching, currentVersion: String, channel: UpdateChannel
    ) async -> UpdateCheckResult {
        do {
            let release: GitHubRelease
            switch channel {
            case .stable:
                release = try await fetcher.fetchLatest()
            case .develop:
                let releases = try await fetcher.fetchLatestIncludingPrerelease()
                guard let newest = releases.first(where: { $0.hasDMG }) else {
                    return .upToDate(current: currentVersion)
                }
                release = newest
            }
            guard let remote = AppVersion(release.tagName),
                  let current = AppVersion(currentVersion),
                  remote > current,
                  release.hasDMG
            else {
                return .upToDate(current: currentVersion)
            }
            return .updateAvailable(
                current: currentVersion,
                latest: release.tagName,
                downloadURL: release.downloadURL
            )
        } catch {
            return .failed
        }
    }
}
```

- [ ] **Step 9: テスト実行で全テスト通過を確認**

Run: `cd BefoldApp && swift test 2>&1 | tail -10`
Expected: 全テスト PASS

- [ ] **Step 10: コミット**

```bash
git add BefoldApp/befold/Updates/UpdateChannel.swift \
       BefoldApp/befold/Updates/UpdateChecker.swift \
       BefoldApp/befold/Updates/ReleaseFetcher.swift \
       BefoldApp/befoldTests/UpdateCheckerTests.swift
git commit -m "feat: UpdateChannel を追加し develop チャンネルで pre-release を検出する"
```

---

### Task 3: `bump.sh` と `/release` スキルの dev 対応

**Files:**
- Modify: `scripts/bump.sh`
- Modify: `.claude/commands/release.md`

**Interfaces:**
- Consumes: 既存の `git tag` 一覧、`project.yml` の `MARKETING_VERSION`
- Produces:
  - `scripts/bump.sh dev`: `v{MARKETING_VERSION}-dev.N` タグを作成・プッシュ（`project.yml` 変更なし）
  - `/release dev`: bump.sh dev → リリースノート → `gh release create --prerelease`

- [ ] **Step 1: `bump.sh` の dev テストをドライランで確認**

まず現状の動作を確認:

```bash
scripts/bump.sh dev --dry-run
```

Expected: エラー（`dev` は patch/minor/major 以外なので弾かれる）

- [ ] **Step 2: `bump.sh` に `dev` 引数を追加**

`scripts/bump.sh` の引数検証部分を変更し、`dev` ケースを追加:

```bash
case "$LEVEL" in
  patch|minor|major|dev) ;;
  *) err "引数は patch | minor | major | dev のいずれかを指定してください（指定値: '${LEVEL}'）" ;;
esac
```

`dev` ケースの処理を、バージョン bump セクションの後（`echo "バージョン:"` の前）に追加:

```bash
if [ "$LEVEL" = "dev" ]; then
  # dev タグの連番を既存タグから算出する
  DEV_PREFIX="v${OLD_VERSION}-dev."
  LAST_DEV=$(git -C "$ROOT" tag --list "${DEV_PREFIX}*" --sort=-v:refname | head -1)
  if [ -n "$LAST_DEV" ]; then
    LAST_N="${LAST_DEV#"$DEV_PREFIX"}"
    NEW_N=$(( LAST_N + 1 ))
  else
    NEW_N=1
  fi
  DEV_TAG="${DEV_PREFIX}${NEW_N}"
  echo "dev タグ: ${DEV_TAG}"

  if $DRY_RUN; then
    echo "(dry-run のためここで終了します)"
    exit 0
  fi

  git -C "$ROOT" tag "$DEV_TAG"
  git -C "$ROOT" push --tags
  echo "${DEV_TAG} をプッシュしました"
  exit 0
fi
```

この `if` ブロックを、`NEW_BUILD` 算出の直前（`OLD_BUILD=...` の前）に挿入する。`dev` の場合は `project.yml` の変更もコミットも不要なのでここで `exit 0` する。

- [ ] **Step 3: ドライランで動作確認**

```bash
scripts/bump.sh dev --dry-run
```

Expected: `dev タグ: v1.4.8-dev.1` と表示され、`(dry-run のためここで終了します)` で終了

- [ ] **Step 4: `/release` スキルを更新**

`.claude/commands/release.md` を以下に更新:

```markdown
# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major | dev）

## 手順

### 1. バージョン bump（またはdev タグ作成）

`/bump` スキルと同じ手順で bump する:

\```bash
scripts/bump.sh $ARGUMENTS
\```

エラー終了した場合はここで停止する（リカバリーしない）。

### 2. リリースノートの生成

`/release-notes` スキルの手順に従い、最新タグと前回タグ間のコミットから
リリースノートを Markdown で生成する。生成結果はユーザーに表示する。

### 3. GitHub リリース作成

最新タグ（`git describe --tags --abbrev=0`）を使い、リリースノートを body にして
GitHub リリースを作成する。

**dev リリースの場合**（タグに `-` が含まれる場合）:

\```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>" --prerelease
\```

**stable リリースの場合**:

\```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>"
\```

DMG のビルドと添付は GitHub Actions（release.yml）が自動で行うため、
ローカルでのビルド・DMG 作成は不要。

各ステップの結果をユーザーに報告する。
```

- [ ] **Step 5: `/bump` スキルも更新**

`.claude/commands/bump.md` の引数説明を更新:

```markdown
# /bump — バージョン bump & リリースタグ

引数: $ARGUMENTS（patch | minor | major | dev）
```

- [ ] **Step 6: コミット**

```bash
git add scripts/bump.sh .claude/commands/release.md .claude/commands/bump.md
git commit -m "feat: bump.sh と /release スキルに dev リリースを追加する"
```
