# Markdown コードブロックのシンタックスハイライト — 設計

## 背景

Markdown 内のコードブロックは現在モノクロ表示になっている。
markdown-it の初期化（`viewer.html`）に `highlight` オプションが設定されておらず、
ハイライトライブラリも同梱されていないため、フェンスは
`<pre><code class="language-xxx">` のプレーン HTML になるだけで色が付かない。

調査の結果、表示面が WKWebView である本アプリでは、既存の
「minified 単一 JS を Resources に同梱して viewer.html から読む」パターン
（mermaid / markdown-it と同じ）に乗る highlight.js が最適と判断した。
ネイティブ実装（Highlightr 等）は highlight.js を JSCore と WKWebView で
二重搭載する形になり合理性がない。

## 要件

1. 言語指定のあるコードブロック（例: ` ```swift `）をシンタックスハイライトする。
2. 言語セットは highlight.js の common ビルド（約 40 言語、単一ファイル約 120KB）。
3. 言語未指定・未対応言語のフェンスは現状通りプレーン表示（自動判定はしない。
   GitHub と同じ挙動）。
4. 配色は GitHub 風テーマ（`github.css` / `github-dark.css`）とし、
   既存の `prefers-color-scheme` によるライト/ダーク切替に追従する。
5. mermaid フェンスの特別扱い（`<pre class="mermaid">` 変換）は無変更で共存する。
6. ネットワークアクセスは増やさない（CSP `script-src 'self'` / `connect-src 'none'`
   のまま、同梱アセットのみで動作）。
7. 単体ソースファイル閲覧（`.swift` 等を直接開く）は本機能のスコープ外
   （次機能として別ブランチで実装）。

## 設計

### 1. 追加アセット（vendored、3 ファイル）

`MmdviewApp/mmdview/Resources/` に以下を追加する。いずれも上流配布物を
**無改変**で置く（棚卸しのため）。

- `highlight.min.js` — highlight.js の common ビルド
  （実装時点の最新 v11 系を採用し、正確なバージョンは `package.json` の
  devDependency と一致させて固定する。IIFE 形式、グローバル `hljs` を登録。
  BSD-3-Clause）
- `github.css` / `github-dark.css` — highlight.js 公式テーマ

ライト/ダーク切替はテーマ CSS を編集せず、`viewer.html` の `<link>` の
`media` 属性で行う:

```html
<link rel="stylesheet" href="github.css" media="(prefers-color-scheme: light)">
<link rel="stylesheet" href="github-dark.css" media="(prefers-color-scheme: dark)">
```

### 2. ハイライト処理（viewer.js + viewer.html）

- ハイライト本体は `viewer.js` に純粋関数として切り出す
  （「viewer.js = テスト可能な純粋ロジック」の既存設計に従う）:

```js
// hljs は依存注入（テスト時は npm の highlight.js を渡す）
function highlightCode(hljs, str, lang) {
  if (hljs && lang && hljs.getLanguage(lang)) {
    try {
      var result = hljs.highlight(str, { language: lang, ignoreIllegals: true });
      return '<pre><code class="hljs language-' + sanitizeLang(lang) + '">'
        + result.value + '</code></pre>';
    } catch (e) { /* フォールバックへ */ }
  }
  return '';
}
```

- `viewer.html` 側:
  - `<script src="highlight.min.js">` を追加（読み込み順は既存 script 群に続ける）。
  - `markdownit({...})` に `highlight` オプションを追加し、
    `highlightCode(typeof hljs !== 'undefined' ? hljs : null, str, lang)` を返す。
- markdown-it の仕様上、`highlight` の返り値が `<pre` で始まる場合はそのまま採用され、
  `''` の場合は markdown-it デフォルトのエスケープ済み `<pre><code>` にフォールバックする
  （公式 README のレシピ）。
- 既存の fence オーバーライド（mermaid 特別扱い）は無変更。mermaid フェンスは
  `defaultFence` に到達する前に `<pre class="mermaid">` へ変換されるため、
  `highlight` オプションが呼ばれることはない。

### 3. スタイルの一貫性

テーマ CSS の `.hljs` は独自の背景色（ライト `#fff` / ダーク `#0d1117`）を持つが、
既存の `#diagram-wrap pre:not(.mermaid) code`（`style.css`）が ID セレクタで
より高い詳細度を持ち `background: none` を当てるため、コードブロックの地色は
既存の `--code-bg`（`#f4f4f4` / `#2d2d2d`）のまま維持される。
ハイライト有無でブロックの見た目（地色・角丸・余白）が揃い、
トークン色だけがテーマから乗る。

style.css は原則無変更。実装時に実表示（ライト/ダーク両方）で確認し、
干渉があれば最小の上書きルールのみ追加する。

### 4. エスケープ経路（XSS）

生文字列がそのまま HTML になる経路は作らない:

- ハイライト成功時 → `hljs.highlight()` がコード内容をエスケープした HTML を返す。
- フォールバック時 → markdown-it デフォルトの `escapeHtml` 経路。
- `class` 属性に埋める言語名 → `sanitizeLang()` で英数字と `_` `+` `-` のみに
  制限した文字列を埋め込む（`hljs.getLanguage()` を通過した言語名のみが
  ここに到達するが、防御的に二重チェックする）。

### 5. ビルド定義

- `Package.swift` — `.copy()` に新規 3 ファイルを追加。
- `project.yml` — `mmdview/Resources` のフォルダ一括コピーのため変更不要。
- `package.json` — devDependencies に `highlight.js`（同梱版と同一バージョン）を追加し、
  Jest から実物でテストする（markdown-it と同じパターン）。

### 6. エラー処理

- `highlight.min.js` の読み込み失敗（`typeof hljs === 'undefined'`）
  → ハイライトなしの従来表示に縮退（既存の `markdownit` ガードと同じパターン）。
- `hljs.highlight()` の例外 → try/catch で `''` フォールバック。
- 未対応言語・言語未指定 → `''` フォールバック（要件 3）。

### 7. テスト

- **Jest**（`__tests__/viewer.test.js` に追加、実物の highlight.js を注入）:
  - 既知言語（swift / javascript）でトークン `<span class="hljs-...">` が付く
  - 返り値が `<pre><code class="hljs language-...">` で始まる
  - 未対応言語 → `''`
  - 言語未指定（空文字 / null）→ `''`
  - `hljs` が null（読み込み失敗相当）→ `''`
  - コード中の `<script>` タグがエスケープされる
- **手動確認**: `sample/` の Markdown サンプルに複数言語のコードブロックを追加し、
  ライト/ダーク両モードで目視確認（mermaid フェンスとの共存も確認）。
- Swift 側は無変更のため既存テストのみ。

### 8. 運用への組み込み

`/check-vendored-deps`（棚卸しスキル）と `vendored-deps-auditor` エージェントの
監査対象に highlight.js（本体 + テーマ CSS 2 ファイル）を追記する。
