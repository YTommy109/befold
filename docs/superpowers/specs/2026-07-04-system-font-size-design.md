# Markdown 本文フォントサイズのシステム設定連動 設計

## 背景

Markdown プレビューの本文フォントが他アプリより小さく見える。原因は 2 つの掛け合わせ:

1. 同梱の `github-markdown.css` が `.markdown-body { font-size: 16px }` を指定(141 行)
2. 全体ズームが `#diagram-wrap` の CSS `zoom` に `ユーザー倍率 × BASE_SCALE(0.75)` を
   適用するため、ズーム 100% 時の実効サイズは **16 × 0.75 = 12px**

macOS の標準本文サイズ(13pt)より小さい。要件は「Mac のシステム設定から取得した
フォントサイズに合わせる」こと。

## 方針

Swift 側で `NSFont.preferredFont(forTextStyle: .body).pointSize` を取得し
(既定 13pt。システム設定 > アクセシビリティ > ディスプレイ > テキストサイズの
変更に追従する API)、既存の `_mmdInitialZoom` と同じ
`.atDocumentStart` の `WKUserScript` で `window._mmdSystemFontSize` として注入する。

JS 側は **`システムサイズ ÷ BASE_SCALE`** を `.markdown-body` の font-size に
CSS 変数経由で適用し、ズーム 100% 時の実効表示サイズがシステムサイズと一致するよう
BASE_SCALE を補正する。見出し等は github-markdown-css が em / % で相対指定して
いるため自動で比例スケールする。

- 適用対象は Markdown 表示(`.markdown-body` 付与時)のみ。`.mmd`(Mermaid 単体)は不変
- 取得タイミングは WebView 生成時。実行中ウィンドウへのライブ反映は対象外
  (OS 設定変更後に開いたウィンドウから反映)
- WKWebView では CSS px = pt(バッキングスケールは WebKit が処理)のため単位変換は不要

### 検討した代替案

- **BASE_SCALE を markdown では外す**: ズームの意味が変わり保存済みズーム値と
  非互換になるため不採用
- **`webView.pageZoom` で 13/16 倍**: mermaid ダイアグラムまで縮小されるため不採用

## 変更内容

### 1. `Viewer/ViewerBridge.swift`

```swift
/// ロード時にシステム本文フォントサイズ(pt)を注入するスクリプト。
static func systemFontSizeScript(_ size: Double) -> String {
    "window._mmdSystemFontSize = \(size);"
}
```

### 2. `Viewer/ViewerWebView.swift`

`makeNSView` で `NSFont.preferredFont(forTextStyle: .body).pointSize` を読み、
`zoomScript` と同様の `WKUserScript`(`.atDocumentStart`, `forMainFrameOnly: true`)
として追加する。

### 3. `Resources/viewer.js` — 純粋関数を追加

```js
// システム本文フォントサイズ(pt)を、BASE_SCALE 込みの実効表示がその
// サイズになる CSS px に変換する。未注入・不正値は従来表示(実効 12px)に縮退。
function markdownFontSize(raw) {
  var s = parseFloat(raw);
  if (isNaN(s) || s <= 0) { s = 16 * BASE_SCALE; }
  return s / BASE_SCALE;
}
```

`module.exports` にも追加する。

### 4. `Resources/viewer.html` — 初期化で CSS 変数を設定

```js
function _mmdInitFontSize() {
  document.documentElement.style.setProperty(
    '--mmd-markdown-font-size',
    markdownFontSize(window._mmdSystemFontSize) + 'px'
  );
}
```

末尾の `_mmdInitZoom();` と並べて `_mmdInitFontSize();` を呼ぶ。

### 5. `Resources/style.css`

既存の `#diagram-wrap.markdown-body` ブロックに font-size を追加し、
ベンダー CSS の固定 px(code/pre の 12px)を相対値に置き換える:

```css
#diagram-wrap.markdown-body {
  --bgColor-default: var(--bg);
  width: 100%;
  max-width: 980px;
  /* システム本文フォントサイズ(BASE_SCALE 補正済み)。未設定時はベンダー既定と同じ 16px */
  font-size: var(--mmd-markdown-font-size, 16px);
}

/* ベンダー CSS の固定 12px(基準 16px の 0.75 倍)を em にし、本文サイズに追従させる */
#diagram-wrap.markdown-body tt,
#diagram-wrap.markdown-body code,
#diagram-wrap.markdown-body samp,
#diagram-wrap.markdown-body pre {
  font-size: 0.75em;
}

/* pre 内の code が 0.75em × 0.75em と二重に縮まないようベンダーの pre code { 100% } を
   ID 詳細度で再現する */
#diagram-wrap.markdown-body pre code,
#diagram-wrap.markdown-body pre tt {
  font-size: 100%;
}
```

ベンダー CSS 内のその他の固定 12px(`.csv-data`、`.footnotes`)は markdown-it の
出力に現れないクラスのため対象外。

## エラーハンドリング・エッジケース

- **`_mmdSystemFontSize` 未注入・不正値**(将来のリグレッションや手動でファイルを
  開いた場合): `markdownFontSize` が 12(実効)にフォールバックし従来表示と同一になる
- **`.mmd` ファイル**: `markdown-body` クラスが付かないため影響なし
- **Markdown 内の mermaid 図**: `pre.mermaid` に 0.75em が掛かるが、mermaid の
  テキストはテーマ設定の明示 px が基本のため影響は軽微。手動確認項目に含める
- **ズームとの独立性**: font-size は静的な CSS 変数、ズームは `style.zoom` で別軸。
  既存のズーム保存値・挙動は不変

## テスト

- **ViewerBridgeTests**(契約テスト):
  - `systemFontSizeScript(13.0)` が `"window._mmdSystemFontSize = 13.0;"` を返す
  - `bridgeFunctionsExistInViewerHTML` に `window._mmdSystemFontSize` の存在チェックを追加
- **Jest**(`__tests__/viewer.test.js`): `markdownFontSize` のテストを追加
  - `markdownFontSize(13)` ≈ 17.333(13 ÷ 0.75)
  - `undefined` / `'abc'` / `0` / 負値 → 16(従来表示への縮退)
- **手動確認**: `/run` でサンプル Markdown を開き、
  1. 本文がシステムのテキストサイズ(既定 13pt)相当で表示される
  2. システム設定 > アクセシビリティ > テキストサイズを変更 → 新規ウィンドウで追従
  3. コードブロック・インラインコードが本文に比例したサイズ
  4. Markdown 内 mermaid 図と `.mmd` 単体表示が従来どおり
  5. ズーム(Cmd +/−、リセット)の挙動が従来どおり
