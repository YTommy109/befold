# ファイル毎のウィンドウ状態・表示倍率の復元 — 設計

## 背景

再起動時に前回開いていたファイルは復元される（`SessionStore`、#65）が、
ウィンドウのサイズ・位置・表示倍率はファイル毎に復元されない。

現状の問題:

- **ウィンドウ位置**: `ViewerWindowController.init` は `setFrameAutosaveName("Viewer-<パス>")`
  でファイル毎のフレーム autosave を設定しているが、直後に `window.center()` を
  無条件で呼ぶため、復元された位置が毎回中央配置で上書きされる。
- **表示倍率**: localStorage の単一キー `mmdview.viewer.zoom` に保存されており、
  全ウィンドウ共通の値になっている（WKWebView の `file://` オリジンを全ウィンドウが共有）。

## 要件

1. ウィンドウのサイズ・位置をファイル毎に保存・復元する（アプリ再起動を跨ぐ）。
2. 表示倍率をファイル毎に保存・復元する（アプリ再起動を跨ぐ）。
3. 保存済み倍率がないファイルは常に 100%（1.0）で開く。
4. 倍率の保存先は UserDefaults（Swift 側）とし、ウィンドウフレーム・セッションと系統を揃える。

## 設計

### 1. ウィンドウ位置・サイズの復元修正

`ViewerWindowController.init` で保存済みフレームの有無を先に確認し、
保存がある場合は `center()` を呼ばない:

```swift
let autosaveName = "Viewer-\(safeName)"
let hasSavedFrame = window.setFrameUsingName(autosaveName)
window.setFrameAutosaveName(autosaveName)
// ...
if !hasSavedFrame { window.center() }  // 初回のみ中央配置
```

保存自体は既存の NSWindow フレーム autosave（ファイルパス毎）をそのまま使う。

### 2. 表示倍率のファイル毎保存

- **新規 `ZoomStore`**（`mmdview/App/ZoomStore.swift`）:
  `SessionStore` と同じパターンの `@MainActor` クラス。
  - UserDefaults キー: `ViewerZoomLevels`、値は `[正規化パス: 倍率]` の辞書。
  - パス正規化は `SessionStore` と同じ `resolvingSymlinksInPath().path`。
  - 読み取り時に範囲外の値を 0.5〜2.0 に clamp（`viewer.js` の `ZOOM_MIN`/`ZOOM_MAX` と同値）。
  - 保存値がないパスは 1.0 を返す。
- **JS → Swift（保存）**: `ViewerWebView` に `WKScriptMessageHandler`（名前: `zoomChanged`）を追加。
  `viewer.html` の `_mmdApplyZoom()` は localStorage への保存をやめ、
  `webkit.messageHandlers.zoomChanged.postMessage(_mmdZoom)` を送信する。
- **Swift → JS（復元）**: WebView 生成時に `WKUserScript`（documentStart）で
  `window._mmdInitialZoom = <保存値>` を注入し、`_mmdInitZoom()` は localStorage
  ではなくこれを読む。未定義なら 1.0。
- localStorage の旧共有値 `mmdview.viewer.zoom` は今後参照せず、移行しない
  （既存ユーザーも初回は 100% で開く）。

### 3. データフロー

```
AppDelegate（ZoomStore を保持）
  → ViewerWindowController(fileURL, zoomStore)
    → ViewerWebView(initialZoom, onZoomChanged)
        JS で倍率変更 → zoomChanged メッセージ → ZoomStore.save(path, zoom)
```

- 倍率エントリはウィンドウフレーム autosave と同様、ファイル削除後も掃除しない（YAGNI）。
- 同一ファイルは同時に 1 ウィンドウのみ（既存仕様）なので、書き込み競合は考慮不要。

### 4. エラー処理

- 保存値が数値でない・範囲外の場合は clamp / デフォルト 1.0 にフォールバック
  （JS 側は既存の `parseStoredZoom` / `clampZoom` を流用）。

### 5. テスト

- **ZoomStore**: Swift Testing で `SessionStoreTests` と同型のユニットテスト
  （UUID サフィックス付き `UserDefaults(suiteName:)` を使用）:
  - 保存値がなければ 1.0 を返す
  - 保存 → 読込がパス毎に独立している
  - インスタンスを跨いで永続化される
  - 範囲外の値は clamp される
- **viewer.js**: 既存 JS テストを `_mmdInitialZoom` 注入方式に合わせて更新
  （純粋関数のテストは流用）。
- **ウィンドウフレーム / WebView ブリッジ**: プロジェクト規約通り GUI 層は
  自動テスト対象外（リリース前手動チェック）。
