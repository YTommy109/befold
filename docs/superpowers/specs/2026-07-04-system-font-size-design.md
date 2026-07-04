# Markdown 本文フォントサイズのシステム設定連動 設計

<!-- supersedes ./2026-07-04-system-font-size-design-v1.md -->

## 背景

Markdown プレビューの本文フォントが他アプリ(GitHub.com、VSCode プレビュー等)より
小さく見える。根本原因:

- `BASE_SCALE = 0.75` は元々「図のデフォルト表示を自然サイズの 75% にする」ために
  導入された(#37, commit `9a175f1`)
- その後 Markdown 本文が同じ `#diagram-wrap` に相乗りし、図専用のはずの 75% 縮小が
  本文にも意図せず波及していた
- 結果: `github-markdown.css` の 16px × 0.75 = **実効 12px** で表示

## 方針（理想解）

BASE_SCALE を `#diagram-wrap` 全体のズームから外し、図の個別ズーム側に移す。

- **変更前**: `#diagram-wrap.style.zoom = userZoom × 0.75`（本文も図も一律 75% 縮小）
- **変更後**: `#diagram-wrap.style.zoom = userZoom`（本文は等倍基準）、
  `.diagram-zoom-inner.style.zoom = perDiagramZoom × 0.75`（図は従来通り 75% 基準）

Markdown 本文のフォントサイズは macOS システム設定に比例させる:

```
markdownFontSize = 16px × (systemBodyPt / 13)
```

- 既定(13pt): **16px**（Web 標準、GitHub/VSCode と同等）
- テキストサイズ拡大時: 比例して大きくなる
- 未注入・不正値: 16px にフォールバック

### 数式的な回帰なし証明

図の視覚サイズ:
- 旧: `naturalHeight × diagramZoom × globalZoom × BASE_SCALE`
- 新: `naturalHeight × (diagramZoom × BASE_SCALE) × globalZoom`
- 両者は乗算の順序が異なるだけで同値

## 変更内容

### 1. `Resources/viewer.js`

```js
// effectiveZoom: BASE_SCALE を外す（図側に移動したため）
function effectiveZoom(zoom) { return zoom; }

// diagramScrollHeight: 図の実寸に BASE_SCALE を掛ける
function diagramScrollHeight(naturalHeight, diagramZoom, viewportHeight, globalZoom) {
  var viewportCap = (viewportHeight - 64) / effectiveZoom(globalZoom);
  return Math.min(naturalHeight * diagramZoom * BASE_SCALE, viewportCap);
}

// markdownFontSize: Web 標準 16px × システム設定比率
var MACOS_DEFAULT_BODY = 13;
var WEB_BASELINE = 16;
function markdownFontSize(raw) {
  var s = parseFloat(raw);
  if (isNaN(s) || s <= 0) { return WEB_BASELINE; }
  return WEB_BASELINE * (s / MACOS_DEFAULT_BODY);
}
```

### 2. `Resources/viewer.html`

Per-diagram zoom に BASE_SCALE を掛ける:

```js
// _mmdApplyDiagramZoom 内
wrap.querySelector('.diagram-zoom-inner').style.zoom = zoom * BASE_SCALE;
```

`_mmdInitFontSize()` と Swift 注入(`_mmdSystemFontSize`)は既存のまま。

### 3. `Viewer/ViewerBridge.swift` / `ViewerWebView.swift`

変更なし。既存の `systemFontSizeScript` と `WKUserScript` 注入をそのまま使用。

### 4. `Resources/style.css`

変更なし。既存の CSS 変数 `--mmd-markdown-font-size` と `font-size: var(...)` をそのまま使用。
コード等の相対サイズ指定(`0.75em`)もそのまま正しく機能する。

## エラーハンドリング・エッジケース

- **`_mmdSystemFontSize` 未注入・不正値**: `markdownFontSize` が 16px を返し、
  Web 標準と同じ表示になる
- **`.mmd` ファイル**: `markdown-body` クラスが付かないため影響なし。図の
  `.diagram-zoom-inner` に `× BASE_SCALE` が掛かるため表示は従来と同一
- **保存済みズーム値**: ユーザーズーム値の意味は変わらない（1.0 = 100%）。
  実効 CSS zoom が変わるため「100% での見た目」は大きくなるが、これが本来の
  意図（100% = 等倍）であり修正
- **ズームとの独立性**: font-size は静的な CSS 変数、ズームは `style.zoom` で別軸

## テスト

- **Jest**: `effectiveZoom`、`diagramScrollHeight`、`markdownFontSize` のテストを
  新しいセマンティクスに更新
- **ViewerBridgeTests**: 変更なし（注入スクリプトのフォーマットは不変）
- **手動確認**: `/run` でサンプル Markdown を開き、
  1. 本文が 16px 相当で表示される（従来の 12px より明確に大きい）
  2. コードブロック・インラインコードが本文に比例したサイズ
  3. Markdown 内 mermaid 図と `.mmd` 単体表示が従来どおり
  4. ズーム(Cmd +/−、リセット)の挙動が従来どおり
  5. ダイアグラム個別ズームの挙動が従来どおり
