# /check-vendored-deps — 同梱 JS ライブラリの棚卸し

`mermaid.min.js` / `markdown-it.min.js` / `highlight.min.js` / `dompurify.min.js`
(+ hljs テーマ CSS `github.css` / `github-dark.css`、Markdown 本文 CSS
`github-markdown.css`)は `BefoldApp/BefoldKit/Resources/` へ手動ベンダリングされており
Dependabot / `npm audit` の監視外。版ずれと既知脆弱性を確認する。
詳細な監査が必要なら `vendored-deps-auditor` サブエージェントに委譲してよい。

## 1. 同梱バージョンを特定する

```bash
scripts/vendored-deps-versions.sh
```

`<名前>\t<同梱版>\t<記録値>` を出力し、同梱ファイルの実バージョンと記録
(`BefoldApp/package.json` / `BefoldKit/Resources/THIRD_PARTY_LICENSES.md`)の
突き合わせまで行う。**パスが消えた・版が抽出できない・記録と食い違う場合は
非ゼロで終了する**ので、`exit 0` でなければ棚卸しの前に手順側を直す。

抽出方法は個別に異なる（スクリプト内のコメント参照）。

| ライブラリ | 版の在り処 | 記録先 |
| --- | --- | --- |
| markdown-it / github-markdown-css / DOMPurify | ファイル先頭のバナーコメント | `package.json` |
| highlight.js | バナー無し。内部の `versionString="…"` | `package.json` |
| mermaid | esbuild バンドルでバナー無し。内部の `version:"…"` | `THIRD_PARTY_LICENSES.md`（`package.json` に **記録が無い**） |
| github.css / github-dark.css | ファイル自身は版を持たない | highlight.js 本体の版に従う |

## 2. 最新版・脆弱性を調べる

- WebSearch で各ライブラリの最新安定版と、同梱版に該当する CVE / GHSA を調べる。
- 実際の初期化設定と突き合わせ、該当 CVE がこのアプリで発火するかを判定する。
  参照先は `viewer.html` ではなく `BefoldApp/viewer-src/markdown.js` / `mermaid.js`。
  - markdown-it: `_mmdInitMarkdown()`（`html: true` / `linkify` / `typographer`）
  - mermaid: `_mmdMermaidConfig()`（`securityLevel: 'strict'` / `maxTextSize` /
    `maxEdges`）。`mermaid.min.js` は `viewer.html` からは読まれず、
    描画が必要になった時点で `mermaid.js` が動的に `<script>` を挿して遅延ロードする
    （ベンダーライブラリは viewer-bundle.js に取り込まず、`viewer.html` から個別に読む）
  - DOMPurify: `md.render` のラッパから `sanitizeRenderedHtml(DOMPurify, …)`
    （`viewer-src/markdown.js`）を通し、**設定なしのデフォルト**で `purify.sanitize()` を呼ぶ
- 脅威モデル: `viewer.html` の CSP は `script-src 'self'`（`'unsafe-inline'` が付くのは
  `style-src` のみ。`ViewerBridgeContractTests` が検証している）。DOMPurify は
  唯一の防御ではなく多層防御の一層であり、サニタイズをすり抜けたインライン
  ハンドラや `<script>` は CSP が実行段階で止める。とはいえ CSP は
  `<img src=x>` 由来の情報漏洩等すべてを止めるわけではないので、
  サニタイズバイパス系 CVE は依然として優先度が高い。

## 3. 報告

ライブラリごとに「同梱版 / 最新版 / 該当 CVE / 更新推奨度」を報告する。
CVE がオプション依存で発火する場合は、更新に加えて設定側の対策も添える。
版ずれも脆弱性もなければ「✅ 同梱依存は最新・既知脆弱性なし」と報告する。
