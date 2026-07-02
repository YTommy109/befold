# Check for Updates 設計 spec

**日付:** 2026-07-02
**対象ブランチ:** feat/auto_update

---

## 概要

<!-- derived-from ./2026-06-03-auto-upgrade-design.md -->

Python 版に存在した「Check for Updates...」メニューを Swift 版 mmdview に復元する。
GitHub Releases API で最新バージョンを確認し、新バージョンがあれば NSAlert で通知して
DMG をダウンロード・インストール・再起動まで自動で行う(Python 版同等)。
開発ビルド(`.app` バンドル外での実行)では自動インストールできないため、
ブラウザでダウンロードページを開くフォールバックにする(Python 版の `not_frozen` 相当)。

チェックのトリガーは 4 つ:

| トリガー | 種別 | キャッシュ | 結果の表示 |
|---------|------|-----------|-----------|
| メニュー「Check for Updates…」 | 手動 | バイパス(毎回取得) | 常に表示(更新あり/最新/エラー) |
| アプリ起動時 | 自動 | TTL 1 時間 | 更新ありのときのみ表示 |
| アプリがアクティブになったとき | 自動 | TTL 1 時間 | 更新ありのときのみ表示 |
| About mmdview 表示時 | 自動 | TTL 1 時間 | 更新ありのときのみ表示 |

自動チェックは「最新です」「確認失敗」を一切表示しない(サイレント)。
手動チェックはユーザーの操作に必ず応答する。

さらに、自動チェックは **同一の新バージョンをセッション中 1 回だけ通知する**。
`didBecomeActive` は起動直後・アラート閉鎖後・ブラウザから戻ったときにも発火するため、
この抑止がないと更新があるあいだ毎回アラートが出てしまう。手動チェックは常に表示する。

---

## アーキテクチャ

```
MmdviewApp/mmdview/Updates/
├── AppVersion.swift              # セマンティックバージョンのパースと比較
├── GitHubRelease.swift           # Releases API レスポンスの Decodable + DMG URL 抽出
├── ReleaseFetcher.swift          # ReleaseFetching プロトコル + URLSession 実装
├── UpdateChecker.swift           # TTL キャッシュ・in-flight 合流・判定ロジック
├── UpdateDownloader.swift        # DMG のストリーミングダウンロード(進捗コールバック)
├── DMGMounter.swift              # hdiutil attach/detach + plist パース + quarantine 除去
├── UpdateInstaller.swift         # インストール先判定・.app 検出・updater スクリプト生成
├── UpdateFlowController.swift    # ダウンロード→確認→インストールのオーケストレーション
├── DownloadProgressWindow.swift  # 進捗ウィンドウ(GUI 層)
└── UpdateUI.swift                # NSAlert 表示(GUI 層)
```

### AppVersion

`"1.1.1"` / `"v1.1.1"` をパースする `Comparable` な struct。
数値配列のタプル比較(桁数が異なる場合は 0 埋め: `1.2 < 1.2.1`)。
パース不能な文字列は `nil`(比較せず「更新なし」に倒す)。

### GitHubRelease

`https://api.github.com/repos/YTommy109/mmdview/releases/latest` のレスポンスをデコードする。

- `tag_name`(先頭の `v` は AppVersion 側で吸収)
- `html_url`(リリースページ)
- `assets[].name` / `assets[].browser_download_url`
- `dmgURL`: 名前が `.dmg` で終わる最初のアセットの URL。なければ `html_url` にフォールバック

### ReleaseFetching / GitHubReleaseFetcher

```swift
protocol ReleaseFetching: Sendable {
    func fetchLatest() async throws -> GitHubRelease
}
```

実装は `URLSession`(タイムアウト 5 秒、`Accept: application/vnd.github+json`)。
テストではモックを注入する(`FileWatching` と同じ DI パターン)。

### UpdateChecker

`@MainActor final class`。依存はイニシャライタ注入:

- `fetcher: ReleaseFetching`(デフォルト: `GitHubReleaseFetcher`)
- `currentVersion: String`(デフォルト: `Bundle.main` の `CFBundleShortVersionString`。
  SPM テスト環境では Info.plist がないため必ず注入可能にする)
- `now: () -> Date`(TTL テスト用クロック)

```swift
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, downloadURL: URL)
    case failed
}

func check(bypassCache: Bool) async -> UpdateCheckResult
```

- **TTL キャッシュ**: 成功結果を 1 時間保持。`bypassCache: true`(手動)は常に再取得
- **in-flight 合流**: チェック実行中に再度呼ばれたら同じ結果を待つ
  (起動時は `didFinishLaunching` と `didBecomeActive` が連続発火するため必須)
- **fail-safe**: 例外はすべて `.failed` に変換。クラッシュ・throw させない

### UpdateDownloader

`URLSession.bytes(from:)` で DMG を一時ディレクトリ
(`FileManager.default.temporaryDirectory/mmdview-update.dmg`)へストリーミング保存する。
64KB ごとに書き出し、`expectedContentLength` が分かる場合は 0.0–1.0 の進捗を
コールバックで通知する。HTTP エラーは throw(呼び出し側でアラート表示)。
`file://` URL でも動作するため、実ファイルを使ったユニットテストが可能。

### DMGMounter

`hdiutil` のラッパー(Python 版 `update_mount.py` 相当):

1. `xattr -d com.apple.quarantine <dmg>` で検疫属性を除去(失敗は無視)
2. `hdiutil attach <dmg> -nobrowse -plist` を実行
3. plist 出力の `system-entities[].mount-point` からマウントポイントを返す

plist パース(`mountPoint(fromPlist:)`)は純粋関数としてユニットテストする。
`Process` 実行はブロッキングのため、呼び出し側で `Task.detached` に載せる。

### UpdateInstaller

インストールの純粋ロジック(Python 版 `update_installer.py` 相当)。すべて static でテスト可能:

- `installedAppURL(bundleURL:)`: 実行中バンドルが `.app` ならその URL、
  それ以外(開発ビルド)は `nil`
- `findApp(inMountPoint:)`: マウントポイント直下の `.app` を探す
- `updaterScript(appInDMG:installedApp:mountPoint:dmgPath:pid:)`: 差し替えスクリプト生成

**updater スクリプトの処理**(`/tmp` 配下に書き出し、`/bin/bash` で起動後 `exit(0)`):

1. 元プロセスの終了を PID ポーリングで待つ(Python 版の固定 3 秒待ちを改善)
2. 旧 `.app` を `rm -rf`、DMG 内の `.app` を `cp -R`
3. `hdiutil detach -force` → DMG 削除 → 新アプリの quarantine 除去 → `open` で再起動
4. スクリプト自身を削除

### UpdateFlowController(GUI 層・自動テスト対象外)

`@MainActor final class`。更新あり時のフロー全体を持ち、`isRunning` で多重起動を防ぐ:

```
askInstall(「ダウンロードしてインストール」/「後で」)
  → 開発ビルドなら: ブラウザで downloadURL を開いて終了
  → DownloadProgressWindow を表示して UpdateDownloader.download
  → askRelaunch(「インストールして再起動」/「後で」)
  → UpdateInstaller で DMG マウント→スクリプト起動→ exit(0)
  → 失敗時: エラーアラート(マウント済みなら detach してから)
```

### DownloadProgressWindow(GUI 層・自動テスト対象外)

`NSPanel` + 確定的 `NSProgressIndicator` の小ウィンドウ(タイトル
「アップデートをダウンロード中…」)。クローズ不可(進捗表示専用)。

### UpdateUI(GUI 層・自動テスト対象外)

`@MainActor` の enum。NSAlert を表示する:

- `askInstall(current:latest:) -> Bool`: 「mmdview v{latest} が利用可能です」
  ボタン: 「ダウンロードしてインストール」/「後で」
- `askRelaunch(latest:) -> Bool`: 「ダウンロードが完了しました」
  ボタン: 「インストールして再起動」/「後で」
- `presentUpToDate` / `presentFailed`(手動チェックのみ)/ `presentInstallFailed`
- 開発ビルドフォールバック: 「開発ビルドのため自動インストールできません。
  ダウンロードページを開きます」→ `NSWorkspace.shared.open(downloadURL)`

---

## トリガー統合

### MainMenuBuilder

App メニューの「About mmdview」直後に追加:

```
About mmdview          → AppDelegate.showAbout(_:) に変更(About + 自動チェック)
Check for Updates…     → AppDelegate.checkForUpdates(_:) 新規
─────────
Services …(既存)
```

`build(openAction:)` のシグネチャは変えず、既存項目と同じくレスポンダチェーン経由で
AppDelegate のセレクタに届く(target 未設定)。

### AppDelegate

- `updateChecker` プロパティを保持
- `applicationDidFinishLaunching`: 自動チェックを起動(Task)
- `applicationDidBecomeActive`: 自動チェック
- `@objc func checkForUpdates(_:)`: 手動チェック(bypassCache)
- `@objc func showAbout(_:)`: `NSApp.orderFrontStandardAboutPanel(sender)` + 自動チェック

自動チェックの結果表示ポリシー(更新ありのときだけ、かつ同一バージョンはセッション中
1 回だけ `UpdateUI` を呼ぶ)は AppDelegate 側の 1 ヘルパー
`runUpdateCheck(userInitiated: Bool)` と `announcedVersion` プロパティに集約する。
手動チェックで表示したバージョンも `announcedVersion` に記録し、直後の自動チェックが
同じ内容を重ねて表示しないようにする。

---

## エラーハンドリング

- ネットワーク・JSON・HTTP エラー: `.failed`。自動チェックではサイレント、手動では通知
- GitHub API レート制限(403/429): 同上(未認証 60 req/h だが TTL 1h で実質問題なし)
- tag のパース不能: `.upToDate` 扱い(誤通知しない方向に倒す)
- ダウンロード・マウント・`.app` 検出の失敗: 進捗ウィンドウを閉じて
  「アップデートのインストールに失敗しました。」を表示(マウント済みなら detach)
- サンドボックス: entitlements は空(非サンドボックス)のため `/Applications` の
  差し替えと `/bin/bash` 起動が可能であることを確認済み

---

## テスト方針

`mmdviewTests/` に Swift Testing で追加(既存パターン踏襲: `@Suite` / `@Test` / `#expect` / モック注入):

- `AppVersionTests`: パース(`v` 付き/不正文字列)・比較(桁違い含む)
- `GitHubReleaseTests`: 実 API 形状の JSON デコード・DMG アセット抽出・フォールバック
- `UpdateCheckerTests`: 更新あり/なし判定、TTL キャッシュ(クロック注入)、
  bypassCache、in-flight 合流、fetcher 例外 → `.failed`
- `UpdateDownloaderTests`: `file://` URL からの実ダウンロード(内容一致・進捗が 1.0 に到達)
- `DMGMounterTests`: `hdiutil -plist` 出力サンプルのマウントポイント抽出・不正 plist で nil
- `UpdateInstallerTests`: インストール先判定(`.app`/開発ビルド)、一時ディレクトリでの
  `.app` 検出、updater スクリプトの内容(PID 待ち・rm/cp/detach/open・自己削除)
- `UpdateUI` / `UpdateFlowController` / `DownloadProgressWindow` / AppDelegate 統合:
  自動テスト対象外(リリース前手動チェック)

---

## スコープ外

- Sparkle 導入(appcast ホスティングと EdDSA 署名のリリースフロー変更が必要)
- 「このバージョンをスキップ」等の抑止設定(UserDefaults 不使用)
- 定期タイマーによるバックグラウンドチェック
- デルタアップデート・コード署名・公証(Notarization)
