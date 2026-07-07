# 行番号表示とボトムバー設計

## 概要

ソースコード表示時に行番号を表示する機能を追加する。ウィンドウ下部にネイティブ AppKit スタイルのボトムバー(ステータスバー)を配置し、行番号の表示/非表示を切り替えるトグルを載せる。ボトムバーは将来の拡張(ファイル情報、エンコーディング表示など)を見据えた構造とする。

## 対象種別

- `.code` — 単一コードファイル(`.swift`, `.py`, `.js` など)
- ソースモード — Markdown / SVG / HTML / CSV のソース表示(`_renderSource`)

レンダリング表示(Markdown の本文表示、ダイアグラム表示など)および画像・PDF は対象外。

## アーキテクチャ

```
ViewerContentView (SwiftUI)
  ├── ViewerWebView          # 既存
  └── ViewerBottomBar        # 新規: ウィンドウ下部のステータスバー
        └── 行番号トグル      # 初期コンテンツ

ViewerStore
  └── showLineNumbers: Bool  # @Observable、UserDefaults で永続化

viewer.js
  └── renderCodeHtml()       # 行番号付き HTML を生成する拡張
  └── renderCsvSourceHtml()  # 行番号付き CSV ソース表示

viewer.html
  └── setLineNumbers(bool)   # JS ブリッジ関数

style.css
  └── .line-numbers          # 行番号ガターのスタイル

ViewerBridge.swift
  └── lineNumbersScript()    # setLineNumbers 呼び出し生成
```

## 詳細設計

### 1. ボトムバー (`ViewerBottomBar.swift`)

SwiftUI ビューとして実装する。`ViewerContentView` の `VStack` 下部に配置する。

- 高さ: 約 22pt(macOS ステータスバー相当)
- 背景: 半透明ブラー(`NSVisualEffectView` 相当)
- 上辺にセパレーター(1px)
- 左寄せで将来のアイテムを並べられるよう `HStack` 構成
- 初期コンテンツ: 行番号トグルボタン(SF Symbol `list.number` / テキストラベル)

表示条件:
- コードファイル(`FileType.code`)表示中、またはソースモード中に表示
- レンダリング表示中(Markdown 本文など)は非表示
- 画像・PDF 表示中も非表示

### 2. 行番号状態管理

`ViewerStore` に `showLineNumbers: Bool` を追加する。

- `@Observable` で UI バインディング
- `UserDefaults` の `ShowLineNumbers` キーで永続化(アプリ全体で共有)
- デフォルト値: `false`(非表示)

### 3. JS 側の行番号表示

#### `renderCodeHtml` の拡張 (viewer.js)

行番号表示時、`<pre>` の中に行番号用の要素を追加する。

```html
<pre><code class="hljs language-swift">
<table class="code-table">
  <tr><td class="line-number">1</td><td class="line-content">import Foundation</td></tr>
  <tr><td class="line-number">2</td><td class="line-content">...</td></tr>
</table>
</code></pre>
```

`<table>` レイアウトを採用する理由:
- 行番号とコード本文を独立してスクロールさせない(同期不要)
- highlight.js のトークンが行をまたぐケースにも対応しやすい
- コピー時に行番号が含まれるのは許容する(不要なら非表示モードでコピーすればよい)

#### `setLineNumbers(show)` 関数 (viewer.html)

```javascript
var _showLineNumbers = false;

function setLineNumbers(show) {
  _showLineNumbers = show;
  if (_lastContent !== null) {
    render(_lastContent, _lastType, _lastLang);
  }
}
```

再描画時に `_showLineNumbers` を参照し、`renderCodeHtml` / `_renderSource` に渡す。

### 4. CSS スタイル (style.css)

```css
.code-table {
  border-collapse: collapse;
  width: 100%;
}

.line-number {
  user-select: none;
  text-align: right;
  padding-right: 1ch;
  color: var(--fg-muted);
  opacity: 0.5;
  min-width: 3ch;
  vertical-align: top;
  white-space: nowrap;
}

.line-content {
  white-space: pre-wrap;
  word-break: break-all;
}
```

### 5. ViewerBridge 拡張

```swift
static func lineNumbersScript(_ show: Bool) -> String {
    "setLineNumbers(\(show))"
}
```

### 6. 状態伝搬の流れ

1. ユーザーがボトムバーのトグルをクリック
2. `ViewerStore.showLineNumbers` がトグル → `UserDefaults` に保存
3. SwiftUI の更新サイクルで `ViewerWebView.updateNSView` が呼ばれる
4. `updateNSView` 内で `ViewerBridge.lineNumbersScript()` を `evaluateJavaScript` で送信
5. JS 側 `setLineNumbers()` が `_showLineNumbers` を更新し、現在のコンテンツを再描画

### 7. メニュー項目

View メニューに「Show Line Numbers」/「行番号を表示」を追加する(ショートカット: Cmd+Shift+L)。

## テスト計画

- **viewer.js ユニットテスト**: `renderCodeHtml` が行番号付き HTML を正しく生成するか
- **ViewerStore テスト**: `showLineNumbers` のトグルと UserDefaults 永続化
- **手動テスト**: ボトムバーの表示/非表示切替、行番号の見た目
