# SVG / HTML 画像表示 & レンダリング/ソース切り替え

## 概要

SVG ファイルを画像として、HTML ファイルをウェブページとしてレンダリング表示し、SVG・HTML・Markdown・Mermaid ファイルでレンダリング表示とソース表示をツールバーボタンで切り替えられるようにする。

## 背景

- SVG は現在 `FileType.code(language: "xml")` として XML シンタックスハイライト表示される
- HTML は未知拡張子として plaintext にフォールバックする
- Markdown / Mermaid はレンダリング表示のみで、ソースを確認する手段がない
- ユーザーはレンダリング結果とソースコードの両方を確認したい

## 設計

### FileType の拡張

`FileType` enum に `.svg` と `.html` case を新設する。

```swift
enum FileType: Sendable, Equatable {
    case mmd
    case markdown
    case svg
    case html
    case code(language: String)
}
```

- `codeExtensionLanguages` から `"svg": "xml"` を除外
- `init(url:)` で `svg` / `html` を code より先に判定
- `jsValue`: `.svg` → `"svg"`, `.html` → `"html"`
- `isRenderable` computed property を追加: `.svg` / `.html` / `.markdown` / `.mmd` → `true`、`.code` → `false`

### viewer.html の変更

#### render() に `type === 'svg'` 分岐を追加

SVG コンテンツを `<img src="data:image/svg+xml;base64,...">` で表示する。`<img>` 経由にすることで SVG 内の `<script>` が実行されずセキュリティ安全。

Mermaid ダイアグラムと同様のズームコントロール（`_mmdWrapDiagrams` 相当）を SVG にも付与する。

#### render() に `type === 'html'` 分岐を追加

HTML コンテンツを `<iframe sandbox srcdoc="...">` で表示する。`sandbox` 属性によりスクリプト実行・フォーム送信・ポップアップを防止。`srcdoc` でインラインに渡すことで外部ファイルアクセスも不要。

#### setViewMode(mode) 関数を新設

```javascript
// mode: 'rendered' | 'source'
function setViewMode(mode) { ... }
```

- 内部状態 `_viewMode` を保持
- 現在の `_lastContent` / `_lastType` / `_lastLang` を使い、適切なモードで再レンダリング
- `mode === 'source'` の場合:
  - SVG → `renderCodeHtml(hljs, content, 'xml')` でシンタックスハイライト
  - HTML → `renderCodeHtml(hljs, content, 'xml')` でシンタックスハイライト
  - Markdown → `renderCodeHtml(hljs, content, 'markdown')`
  - Mermaid → `renderCodeHtml(hljs, content, 'mermaid')` (highlight.js に mermaid がなければ plaintext)
- `mode === 'rendered'` の場合: 通常の render() と同じレンダリング

#### render() の修正

`render()` 呼び出し時に `_lastContent` / `_lastType` / `_lastLang` を保存し、現在の `_viewMode` に応じてレンダリングする。ファイルが変わったら `_viewMode` を `'rendered'` にリセットする。

### Swift 側: ツールバーボタン

`ViewerWindowController` の NSToolbar に toggle ボタンを追加する。

- **アイコン**: SF Symbols `chevron.left.forwardslash.chevron.right`（`</>`）
- **表示条件**: `FileType.isRenderable` が `true` のときのみ表示
- **動作**: タップで `evaluateJavaScript("setViewMode('source')")` / `evaluateJavaScript("setViewMode('rendered')")` を呼び出し
- **状態表示**: ボタンの選択状態（`.state = .on / .off`）で現在のモードを示す

### ViewerBridge の変更

`renderScript()` は既存のまま。新たに `viewModeScript(mode:)` を追加し、`setViewMode()` の JS 呼び出しを生成する。

### デフォルト動作

| ファイルタイプ | デフォルト表示 | トグルで切り替え先 | ツールバーボタン |
|---|---|---|---|
| `.svg` | レンダリング（画像） | XML ソース | 表示 |
| `.html` | レンダリング（sandbox iframe） | HTML ソース | 表示 |
| `.markdown` | レンダリング（HTML） | Markdown ソース | 表示 |
| `.mmd` | レンダリング（ダイアグラム） | Mermaid ソース | 表示 |
| `.code` | コード表示 | — | 非表示 |

### セキュリティ

- SVG は `<img>` タグ経由で表示し、SVG 内の `<script>` 実行を防止
- HTML は `<iframe sandbox>` で表示し、スクリプト実行・フォーム送信・ポップアップを防止
- CSP の `img-src` に `data:` は既に許可済み
- ソース表示は既存の `renderCodeHtml()` + `_escapeHtml()` を使うため XSS リスクなし
