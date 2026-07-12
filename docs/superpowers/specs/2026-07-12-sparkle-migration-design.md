# 自動アップデートを Sparkle 2 に移行する

Issue: [#182](https://github.com/YTommy109/befold/issues/182)

## 背景

現在の自動アップデートは `BefoldApp/befold/Updates/` に 13 ファイルの自前実装（GitHub Releases API → DMG ダウンロード → hdiutil マウント → 署名検証 → 置換スクリプト）で構成されている。リトライ・エラーハンドリング・ログの不足により時々更新に失敗する事象がある。

独自コードの保守を続けるより、macOS で広く使われている Sparkle 2 に置き換えて保守負荷を削減する。

## 方針

- **アプローチ A: Sparkle 標準 UI フル活用** を採用
- `SPUStandardUpdaterController` をそのまま使い、自前 UI を全廃
- `UpdateChannel`（stable/develop の feedURL 切替）のみアプリ固有ロジックとして残す
- `UpdateCheckCoordinator` の通知ポリシーは Sparkle に全委任

## 依存追加

- **Package.swift**: `https://github.com/sparkle-project/Sparkle` を SPM 依存として追加（`from: "2.0.0"`）。befold ターゲットに `Sparkle` プロダクトを依存追加
- **project.yml**: befold ターゲットの `dependencies` に Sparkle SPM パッケージを追加
- Sparkle は befold 初のランタイム SPM 依存となる

## Info.plist

追加するキー:

- `SUFeedURL` — `https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`（stable 用デフォルト）
- `SUPublicEDKey` — EdDSA 公開鍵（`generate_keys` で生成した値）

## アプリコード変更

### 残すファイル（1 ファイル）

**`UpdateChannel.swift`** を改修して残す:

- enum 定義（`.stable` / `.develop`）と UserDefaults 永続化はそのまま
- 既存の `read(from:)` メソッドはそのまま残す
- `feedURLString: String` computed property を追加（Sparkle の `feedURLString(for:)` delegate が `String?` を返すため `String` で統一）
  - `.stable` → `"https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml"`
  - `.develop` → `"https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml"`

### AppDelegate の変更

- `SPUStandardUpdaterController` をプロパティとして保持
- `applicationDidFinishLaunching` で初期 feedURL を設定（`UpdateChannel.read(from: .standard).feedURLString`）
- 「Check for Updates…」メニューのアクションを `updaterController.checkForUpdates(_:)` に接続
- `SPUUpdaterDelegate` を実装し、`feedURLString(for:)` で `UpdateChannel` に応じた URL を返す
- `#if DEBUG` 時は `updaterController.updater.automaticallyChecksForUpdates = false` を設定
- `UpdateCheckCoordinator` への参照をすべて削除

### 削除対象（13 ファイル）

Updates/ 配下 12 ファイル:

- `ReleaseFetcher.swift`
- `GitHubRelease.swift`
- `URLResponse+Validation.swift`
- `UpdateChecker.swift`
- `UpdateDownloader.swift`
- `DMGMounter.swift`
- `CodeSignatureVerifier.swift`
- `UpdateInstaller.swift`
- `UpdateFlowController.swift`
- `UpdateUI.swift`
- `DownloadProgressWindow.swift`
- `AppVersion.swift`

App/ 配下 1 ファイル:

- `UpdateCheckCoordinator.swift`

## テスト変更

### 削除対象（7 ファイル）

- `GitHubReleaseTests.swift`
- `URLResponseValidationTests.swift`
- `UpdateCheckerTests.swift`（`UpdateChannelTests` suite を含む）
- `UpdateInstallerTests.swift`
- `DMGMounterTests.swift`
- `UpdateDownloaderIntegrationTests.swift`
- `UpdateInstallerIntegrationTests.swift`
- `AppVersionTests.swift`

### 新規テスト（1 ファイル）

**`UpdateChannelTests.swift`** を独立ファイルとして作成:

- `UpdateCheckerTests.swift` 内の既存 `UpdateChannelTests` suite を移動
- `feedURLString` プロパティのテストを追加（stable → appcast.xml URL、develop → appcast-develop.xml URL）

### テスト対象外

- Sparkle の UI 動作（更新チェック → ダウンロード → インストール）はリリース前の手動テストで確認

## CI/CD パイプライン変更

### release.yml

既存フロー（DMG 作成 → notarize → staple → codesign 検証 → GitHub Release 公開）の後に追加:

1. **Sparkle ツールのインストール**: `brew install sparkle` で `generate_appcast` / `sparkle sign` CLI を取得
2. **DMG に EdDSA 署名**: `sparkle sign <dmg>` で署名生成。`SPARKLE_PRIVATE_KEY` シークレットを環境変数に設定
3. **appcast 更新（インクリメンタル方式）**:
   - 固定リリース（タグ `appcast`）から既存の `appcast.xml` と `appcast-develop.xml` をダウンロード（初回は空ファイルから開始）
   - 今回リリースした DMG を署名済みの状態でローカルディレクトリに配置
   - `generate_appcast` を実行し、既存 appcast にエントリを追加
   - stable/develop の分離: `generate_appcast` を 2 回実行する。stable 用は prerelease DMG を入力ディレクトリに含めない。develop 用は全 DMG を含める
   - タグに `-` を含むリリースは prerelease として扱う（既存の `softprops/action-gh-release` の挙動と一致）
4. **appcast アップロード**: 固定リリース（タグ `appcast`）のアセットとして `appcast.xml` と `appcast-develop.xml` をアップロード・上書き

### シークレット

- `SPARKLE_PRIVATE_KEY` — ローカルで `generate_keys` を実行して生成した EdDSA 秘密鍵を GitHub Actions Secret に格納

### 既存ステップへの影響

- DMG 作成・notarize・staple・codesign 検証は変更なし
- `softprops/action-gh-release` による DMG 公開も変更なし

## 削除されるコードの規模

- ソースファイル: 13 ファイル削除、1 ファイル改修
- テストファイル: 8 ファイル削除、1 ファイル新規作成
- 合計: 21 ファイル削除、2 ファイル変更/新規
