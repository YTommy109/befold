# Check for Updates 設計 spec

**日付:** 2026-07-02
**対象ブランチ:** feat/auto_update

---

## 概要

<!-- derived-from ./2026-06-03-auto-upgrade-design.md -->

Python 版に存在した「Check for Updates...」メニューを Swift 版 mmdview に復元する。
GitHub Releases API で最新バージョンを確認し、新バージョンがあれば NSAlert で通知して
ブラウザでダウンロードページ(DMG)を開く。**アプリ内での自動インストールは行わない**
(スコープ外。将来の拡張点として設計上は分離しておく)。

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
├── AppVersion.swift          # セマンティックバージョンのパースと比較
├── GitHubRelease.swift       # Releases API レスポンスの Decodable + DMG URL 抽出
├── ReleaseFetcher.swift      # ReleaseFetching プロトコル + URLSession 実装
├── UpdateChecker.swift       # TTL キャッシュ・in-flight 合流・判定ロジック
└── UpdateUI.swift            # NSAlert 表示 + ブラウザ起動(GUI 層)
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

### UpdateUI(GUI 層・自動テスト対象外)

`@MainActor` の enum。`UpdateCheckResult` を受け取り NSAlert を表示する:

- `.updateAvailable`: 「mmdview v{latest} が利用可能です(現在 v{current})」
  ボタン: 「ダウンロード」(=`NSWorkspace.shared.open(downloadURL)`)/「後で」
- `.upToDate`: 「最新バージョンです(v{current})」(手動チェックのみ)
- `.failed`: 「アップデートの確認に失敗しました。」(手動チェックのみ)

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

---

## テスト方針

`mmdviewTests/` に Swift Testing で追加(既存パターン踏襲: `@Suite` / `@Test` / `#expect` / モック注入):

- `AppVersionTests`: パース(`v` 付き/不正文字列)・比較(桁違い含む)
- `GitHubReleaseTests`: 実 API 形状の JSON デコード・DMG アセット抽出・フォールバック
- `UpdateCheckerTests`: 更新あり/なし判定、TTL キャッシュ(クロック注入)、
  bypassCache、in-flight 合流、fetcher 例外 → `.failed`
- `UpdateUI` / AppDelegate 統合: 自動テスト対象外(リリース前手動チェック)

---

## スコープ外

- DMG の自動ダウンロード・インストール・再起動(Python 版にあった機能。将来
  `UpdateCheckResult.updateAvailable` を起点に追加できる)
- Sparkle 導入(appcast ホスティングと EdDSA 署名のリリースフロー変更が必要)
- 「このバージョンをスキップ」等の抑止設定(UserDefaults 不使用)
- 定期タイマーによるバックグラウンドチェック
