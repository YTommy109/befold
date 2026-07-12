# Sparkle 2 移行 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自前の自動アップデート実装（13 ソースファイル + 7 テストファイル）を Sparkle 2 に置き換え、保守負荷を削減する

**Architecture:** Sparkle の `SPUStandardUpdaterController` を使い、標準 UI に全委任する。アプリ固有ロジックは `UpdateChannel`（stable/develop の feedURL 切替）のみ残す。`AppDelegate` が `SPUUpdaterDelegate` を実装し、チャネルに応じた feedURL を返す。

**Tech Stack:** Swift 6 / Sparkle 2 (SPM) / GitHub Actions

## Global Constraints

- macOS 14.0+ deployment target
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- テストは Swift Testing フレームワーク（XCTest ではない）
- テスト関数名は英語 camelCase、日本語説明は `@Test("...")` 表示名で付ける
- Conventional Commits + 日本語
- `SUPublicEDKey` の値はユーザーがローカルで `generate_keys` を実行して生成する（プランではプレースホルダ `PLACEHOLDER_PUBLIC_KEY` を使う）

---

### Task 1: Sparkle SPM 依存を追加し UpdateChannel に feedURLString を実装する

**Files:**
- Modify: `BefoldApp/Package.swift`
- Modify: `BefoldApp/project.yml`
- Modify: `BefoldApp/befold/Updates/UpdateChannel.swift`
- Create: `BefoldApp/befoldTests/UpdateChannelTests.swift`

**Interfaces:**
- Produces: `UpdateChannel.feedURLString: String` — Task 2 の `AppDelegate` が `SPUUpdaterDelegate.feedURLString(for:)` の戻り値として使う

- [ ] **Step 1: Package.swift に Sparkle 依存を追加する**

`BefoldApp/Package.swift` の `dependencies` 配列に Sparkle を追加し、`befold` ターゲットの `dependencies` にも追加する:

```swift
// package-level dependencies
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
],
```

```swift
// befold target dependencies
.executableTarget(
    name: "befold",
    dependencies: [
        "BefoldKit",
        .product(name: "Sparkle", package: "Sparkle"),
    ],
```

- [ ] **Step 2: project.yml に Sparkle パッケージ依存を追加する**

`BefoldApp/project.yml` のトップレベルに `packages` セクションを追加し、`befold` ターゲットの `dependencies` に追加する:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.0.0"
```

befold ターゲットの `dependencies` を更新:

```yaml
    dependencies:
      - target: BefoldKit
      - package: Sparkle
```

- [ ] **Step 3: ビルドして Sparkle の解決を確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: ビルド成功。Sparkle パッケージがフェッチ・解決される。

- [ ] **Step 4: UpdateChannelTests.swift を作成し、feedURLString のテストを書く**

`BefoldApp/befoldTests/UpdateChannelTests.swift` を新規作成。既存の `UpdateCheckerTests.swift` 内の `UpdateChannelTests` suite を移動し、`feedURLString` のテストを追加する:

```swift
import Testing

@testable import befold

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

    @Test("stable チャネルの feedURLString は appcast.xml を指す")
    func stableFeedURLString() {
        #expect(UpdateChannel.stable.feedURLString ==
            "https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml")
    }

    @Test("develop チャネルの feedURLString は appcast-develop.xml を指す")
    func developFeedURLString() {
        #expect(UpdateChannel.develop.feedURLString ==
            "https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml")
    }
}
```

- [ ] **Step 5: テストを実行して失敗を確認する**

Run: `cd BefoldApp && swift test --filter UpdateChannelTests 2>&1 | tail -20`
Expected: `stableFeedURLString` と `developFeedURLString` が `feedURLString` が未定義のためコンパイルエラーで失敗。

- [ ] **Step 6: UpdateChannel に feedURLString を実装する**

`BefoldApp/befold/Updates/UpdateChannel.swift` に computed property を追加:

```swift
import Foundation

enum UpdateChannel: String, Sendable {
    case stable
    case develop

    static func read(from defaults: UserDefaults = .standard) -> UpdateChannel {
        defaults.string(forKey: "UpdateChannel")
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    var feedURLString: String {
        switch self {
        case .stable:
            return "https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml"
        case .develop:
            return "https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml"
        }
    }
}
```

既存のドキュメントコメント `/// アップデートチェックの対象チャンネル(安定版 / 開発版)。` は削除する（コード規約: デフォルトでコメントは書かない）。

- [ ] **Step 7: テストを実行して全テストがパスすることを確認する**

Run: `cd BefoldApp && swift test --filter UpdateChannelTests 2>&1 | tail -20`
Expected: 5 テストすべて PASS。

- [ ] **Step 8: コミットする**

```bash
cd BefoldApp
git add Package.swift project.yml befold/Updates/UpdateChannel.swift befoldTests/UpdateChannelTests.swift
git commit -m "feat: Sparkle 2 依存を追加し UpdateChannel に feedURLString を実装する"
```

---

### Task 2: AppDelegate に Sparkle を統合し、旧アップデートコードを削除する

**Files:**
- Modify: `BefoldApp/befold/App/AppDelegate.swift`
- Modify: `BefoldApp/befold/Info.plist`
- Delete: `BefoldApp/befold/Updates/ReleaseFetcher.swift`
- Delete: `BefoldApp/befold/Updates/GitHubRelease.swift`
- Delete: `BefoldApp/befold/Updates/URLResponse+Validation.swift`
- Delete: `BefoldApp/befold/Updates/UpdateChecker.swift`
- Delete: `BefoldApp/befold/Updates/UpdateDownloader.swift`
- Delete: `BefoldApp/befold/Updates/DMGMounter.swift`
- Delete: `BefoldApp/befold/Updates/CodeSignatureVerifier.swift`
- Delete: `BefoldApp/befold/Updates/UpdateInstaller.swift`
- Delete: `BefoldApp/befold/Updates/UpdateFlowController.swift`
- Delete: `BefoldApp/befold/Updates/UpdateUI.swift`
- Delete: `BefoldApp/befold/Updates/DownloadProgressWindow.swift`
- Delete: `BefoldApp/befold/Updates/AppVersion.swift`
- Delete: `BefoldApp/befold/App/UpdateCheckCoordinator.swift`
- Delete: `BefoldApp/befoldTests/GitHubReleaseTests.swift`
- Delete: `BefoldApp/befoldTests/URLResponseValidationTests.swift`
- Delete: `BefoldApp/befoldTests/UpdateCheckerTests.swift`
- Delete: `BefoldApp/befoldTests/UpdateInstallerTests.swift`
- Delete: `BefoldApp/befoldTests/DMGMounterTests.swift`
- Delete: `BefoldApp/befoldTests/UpdateDownloaderIntegrationTests.swift`
- Delete: `BefoldApp/befoldTests/UpdateInstallerIntegrationTests.swift`
- Delete: `BefoldApp/befoldTests/AppVersionTests.swift`

**Interfaces:**
- Consumes: `UpdateChannel.feedURLString: String` (from Task 1)

- [ ] **Step 1: Info.plist に Sparkle 用キーを追加する**

`BefoldApp/befold/Info.plist` の `<dict>` 内に以下を追加する（`</dict>` の直前）:

```xml
<key>SUFeedURL</key>
<string>https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>PLACEHOLDER_PUBLIC_KEY</string>
```

`PLACEHOLDER_PUBLIC_KEY` はユーザーが `generate_keys` で生成した公開鍵に後で差し替える。

- [ ] **Step 2: AppDelegate を書き換えて Sparkle を統合する**

`BefoldApp/befold/App/AppDelegate.swift` を以下のように変更する:

1. `import Sparkle` を追加
2. `private let updateCoordinator = UpdateCheckCoordinator()` を削除し、以下に置き換える:

```swift
private let updaterController: SPUStandardUpdaterController

// init() 内で初期化:
let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
self.updaterController = updaterController
```

3. `init()` の `super.init()` の後に delegate 設定を追加:

```swift
super.init()
updaterController.updaterDelegate = self
```

4. `applicationDidFinishLaunching` 内の `updateCoordinator.run(userInitiated: false)` を以下に置き換える:

```swift
#if DEBUG
    updaterController.updater.automaticallyChecksForUpdates = false
#endif
updaterController.startUpdater()
```

5. `applicationDidBecomeActive` 内の `updateCoordinator.run(userInitiated: false)` を削除（Sparkle が自動チェックを管理する）

6. `showAbout` 内の `updateCoordinator.run(userInitiated: false)` を削除

7. `checkForUpdates(_:)` の実装を変更:

```swift
@objc func checkForUpdates(_ sender: Any?) {
    updaterController.checkForUpdates(sender)
}
```

8. ファイル末尾に `SPUUpdaterDelegate` extension を追加:

```swift
extension AppDelegate: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.read(from: .standard).feedURLString
    }
}
```

- [ ] **Step 3: 旧アップデートのソースファイル 12 個を削除する**

```bash
cd BefoldApp
rm befold/Updates/ReleaseFetcher.swift
rm befold/Updates/GitHubRelease.swift
rm befold/Updates/URLResponse+Validation.swift
rm befold/Updates/UpdateChecker.swift
rm befold/Updates/UpdateDownloader.swift
rm befold/Updates/DMGMounter.swift
rm befold/Updates/CodeSignatureVerifier.swift
rm befold/Updates/UpdateInstaller.swift
rm befold/Updates/UpdateFlowController.swift
rm befold/Updates/UpdateUI.swift
rm befold/Updates/DownloadProgressWindow.swift
rm befold/Updates/AppVersion.swift
```

- [ ] **Step 4: UpdateCheckCoordinator.swift を削除する**

```bash
rm befold/App/UpdateCheckCoordinator.swift
```

- [ ] **Step 5: 旧アップデートのテストファイル 7 個を削除する**

```bash
rm befoldTests/GitHubReleaseTests.swift
rm befoldTests/URLResponseValidationTests.swift
rm befoldTests/UpdateCheckerTests.swift
rm befoldTests/UpdateInstallerTests.swift
rm befoldTests/DMGMounterTests.swift
rm befoldTests/UpdateDownloaderIntegrationTests.swift
rm befoldTests/UpdateInstallerIntegrationTests.swift
rm befoldTests/AppVersionTests.swift
```

- [ ] **Step 6: ビルドして成功を確認する**

Run: `cd BefoldApp && swift build 2>&1 | tail -20`
Expected: ビルド成功。旧コードへの参照がすべて解消されていること。

- [ ] **Step 7: テストを実行して全テストがパスすることを確認する**

Run: `cd BefoldApp && swift test 2>&1 | tail -20`
Expected: 全テスト PASS。削除したテストファイルに関するエラーがないこと。

- [ ] **Step 8: コミットする**

```bash
cd BefoldApp
git add -A
git commit -m "feat: Sparkle 2 に統合し、旧自動アップデート実装を削除する"
```

---

### Task 3: リリース CI に appcast 生成ステップを追加する

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: なし（CI のみの変更）

- [ ] **Step 1: release.yml に Sparkle ツールインストールと appcast 生成ステップを追加する**

`.github/workflows/release.yml` の末尾（`softprops/action-gh-release` ステップの後）に以下のステップを追加する:

```yaml
      - name: Sparkle ツールをインストールする
        run: brew install sparkle

      - name: DMG の EdDSA 署名を生成する
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          signature=$(echo -n "$SPARKLE_PRIVATE_KEY" | sparkle sign --ed-key-file - "../$DMG_NAME")
          echo "SPARKLE_SIGNATURE=$signature" >> "$GITHUB_ENV"
          echo "DMG_LENGTH=$(stat -f%z "../$DMG_NAME")" >> "$GITHUB_ENV"

      - name: appcast を生成する
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          version="${GITHUB_REF_NAME#v}"
          tag_name="${GITHUB_REF_NAME}"
          download_url="https://github.com/YTommy109/befold/releases/download/${tag_name}/${DMG_NAME}"
          is_prerelease=${{ contains(github.ref_name, '-') }}

          # 既存の appcast をダウンロード（初回は空で開始）
          gh release download appcast -p "appcast.xml" -D "$RUNNER_TEMP" 2>/dev/null || echo '<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>befold</title></channel></rss>' > "$RUNNER_TEMP/appcast.xml"
          gh release download appcast -p "appcast-develop.xml" -D "$RUNNER_TEMP" 2>/dev/null || echo '<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>befold</title></channel></rss>' > "$RUNNER_TEMP/appcast-develop.xml"

          # 新しいエントリの XML フラグメントを生成
          pub_date=$(date -R)
          item="<item><title>befold ${version}</title><sparkle:version>${CURRENT_PROJECT_VERSION:-$(git rev-list --count HEAD)}</sparkle:version><sparkle:shortVersionString>${version}</sparkle:shortVersionString><pubDate>${pub_date}</pubDate><enclosure url=\"${download_url}\" sparkle:edSignature=\"${SPARKLE_SIGNATURE}\" length=\"${DMG_LENGTH}\" type=\"application/octet-stream\" /></item>"

          # develop 用 appcast（全リリース含む）に追加
          sed -i '' "s|</channel>|${item}</channel>|" "$RUNNER_TEMP/appcast-develop.xml"

          # stable 用 appcast（prerelease を除外）
          if [ "$is_prerelease" = "false" ]; then
            sed -i '' "s|</channel>|${item}</channel>|" "$RUNNER_TEMP/appcast.xml"
          fi

      - name: appcast を固定リリースにアップロードする
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # appcast リリースが存在しなければ作成
          gh release view appcast 2>/dev/null || gh release create appcast --title "Appcast" --notes "Sparkle appcast files (自動更新)" --latest=false

          # アセットをアップロード（既存があれば上書き）
          gh release upload appcast "$RUNNER_TEMP/appcast.xml" "$RUNNER_TEMP/appcast-develop.xml" --clobber
```

- [ ] **Step 2: コミットする**

```bash
git add .github/workflows/release.yml
git commit -m "ci: リリース CI に Sparkle appcast 生成ステップを追加する"
```

- [ ] **Step 3: CI ワークフローの YAML 文法を検証する**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML valid"`
Expected: `YAML valid`
