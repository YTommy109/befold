# github-markdown-css 導入設計

## 背景

Markdown プレビューの表が他エディタのプレビューや GitHub と比べて行間が詰まって見える。
原因は表固有ではなく、`style.css` のグローバルリセット(`* { margin: 0; padding: 0 }`)と
`line-height` 未指定(WebKit デフォルト約 1.2)により、Markdown レンダリング全体が
GitHub(`line-height: 1.5`、ブロック要素の余白 16px)より詰まっていること。

要件は「GitHub で見えるのとの類似性が高いこと」。自前でスタイルを調整するのではなく、
GitHub 本家のスタイルから自動生成されている既製 CSS を採用する。

## 方針

[github-markdown-css](https://github.com/sindresorhus/github-markdown-css) **v5.9.0**
(MIT ライセンス)の auto バリアント `github-markdown.css` をベンダリングする。
`@media (prefers-color-scheme)` によるライト/ダーク自動切替で、既存 `style.css` の
配色機構と同じ仕組み。

- 適用対象は Markdown レンダリング時の `#diagram-wrap` のみ(`markdown-body` クラスを動的付与)
- `.mmd`(Mermaid 単体)表示には適用しない
- 背景色はアプリ現行色(`--bg`: ライト `#fff` / ダーク `#1e1e1e`)を維持する
  (github-markdown-css のダーク背景 `#0d1117` には合わせない)

## 変更内容

### 1. `Resources/github-markdown.css` の追加(新規)

npm パッケージ `github-markdown-css@5.9.0` の `github-markdown.css` をそのまま配置。
ファイル先頭にバージョン照合用バナーを追記する:

```css
/*! github-markdown-css v5.9.0 | MIT | https://github.com/sindresorhus/github-markdown-css */
```

### 2. `viewer.html` の変更

- `<head>` の `style.css` の**前**に `<link rel="stylesheet" href="github-markdown.css">` を追加。
  読み込み順を `github-markdown.css → github.css / github-dark.css(hljs テーマ)→ style.css`
  とし、`style.css` の上書きが常に後勝ちになるようにする
- `render(content, type)` でコンテナのクラスを切り替える:
  - Markdown レンダリング時: `diagramWrap.classList.add('markdown-body')`
  - `type === 'mmd'` 時: `diagramWrap.classList.remove('markdown-body')`

### 3. `style.css` の変更

- 「Markdown 表示の最小限のダーク対応」ブロック(`#diagram-wrap` 配下の
  a / code / pre / blockquote / hr / table スタイル、現 190-239 行)を削除。
  役目は github-markdown-css に移る。これらのセレクタは JS / Swift から参照されて
  いないため削除安全(調査済み)
- 上書きブロックを追加:

```css
/* github-markdown-css の背景をアプリ現行色に差し替え、GitHub 推奨幅を適用する */
#diagram-wrap.markdown-body {
  --bgColor-default: var(--bg);
  width: 100%;
  max-width: 980px;
}

/* Markdown 内の mermaid 図(pre.mermaid)にはコードブロック背景を付けない */
#diagram-wrap.markdown-body pre.mermaid {
  background: none;
  padding: 0;
}

/* hljs テーマの .hljs 背景を無効化し、pre の背景(GitHub と同じ muted 色)を見せる */
#diagram-wrap.markdown-body code.hljs {
  background: transparent;
}
```

`--bgColor-default` は `.markdown-body` の背景のほか、テーブルのスティッキーヘッダ等でも
参照されるため、`background` 直接指定ではなく変数の差し替えで統一する。
テキスト色・罫線色・ゼブラ縞などは github-markdown-css の値をそのまま使う
(ダーク時のアプリ背景 `#1e1e1e` と GitHub の前景色のコントラストは十分)。

`--code-bg` / `--border-subtle` / `--table-border` / `--link` 変数は Markdown 用途では
不要になるが、他の UI(エラーパネル等)で使われていないものだけ削除する。

### 4. `Package.swift` の変更

`resources` に `.copy("Resources/github-markdown.css")` を追記
(SwiftPM はリソースを明示列挙するため必須。`project.yml` はディレクトリごとコピーのため変更不要)。

### 5. バージョン管理・棚卸し対象への登録

- `MmdviewApp/package.json` の `devDependencies` に `"github-markdown-css": "5.9.0"` を追記
- `.claude/commands/check-vendored-deps.md` と `.claude/agents/vendored-deps-auditor.md`
  の棚卸し対象リストに `github-markdown.css` を追記(先頭バナーで版を照合)

## エラーハンドリング・エッジケース

- **Markdown 内の mermaid ブロック**: fence ルールが `<pre class="mermaid">` を出力し
  `mermaid.run()` が中身を SVG に置換する。`pre` 要素自体は残るため、上記の背景打ち消しで
  コードブロック風の背景が付くのを防ぐ
- **`.mmd` ファイル**: `markdown-body` クラスを付けないため見た目は現状と完全に同一
- **ズーム**: `#diagram-wrap` への `style.zoom` 操作はクラス付与と独立しており影響なし
- **CSP**: `style-src 'self' 'unsafe-inline'` のため同梱 CSS の読み込みは許可済み

## テスト

- 既存の自動テスト(Swift Testing / Jest)は viewer.html の CSS 構成を検証していないため、
  この変更で壊れるテストはない。新規の自動テストも追加しない(WebView/GUI 層は
  リリース前手動チェックの方針に従う)
- 手動確認: `/run` でサンプル Markdown(表・コードブロック・mermaid ブロック入り)と
  `.mmd` ファイルを開き、ライト/ダーク両方で以下を確認する
  1. 表の行間・ゼブラ縞・罫線が GitHub と同等
  2. 段落・見出し・リストの余白が GitHub と同等
  3. コードブロックのシンタックスハイライトの配色が崩れていない
  4. Markdown 内 mermaid 図と `.mmd` 単体表示が従来どおり
  5. 背景色がアプリ現行色のまま
