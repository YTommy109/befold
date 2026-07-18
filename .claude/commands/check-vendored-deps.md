# /check-vendored-deps — 同梱 JS ライブラリの棚卸し

`mermaid.min.js` / `markdown-it.min.js` / `highlight.min.js` / `dompurify.min.js`(+ テーマ CSS `github.css` / `github-dark.css`、Markdown 本文 CSS `github-markdown.css`)は手動ベンダリングで Dependabot の監視外。
版ずれと既知脆弱性を確認する。詳細な監査が必要なら `vendored-deps-auditor`
サブエージェントに委譲してよい。

## 1. 同梱バージョンを特定する

```bash
head -1 BefoldApp/befold/Resources/markdown-it.min.js
head -1 BefoldApp/befold/Resources/github-markdown.css
grep -o '"version":"[0-9.]*"' BefoldApp/befold/Resources/mermaid.min.js | head -1
grep -o 'versionString="[0-9.]*"' BefoldApp/befold/Resources/highlight.min.js | head -1
head -1 BefoldApp/BefoldKit/Resources/dompurify.min.js
grep -E 'markdown-it|mermaid|highlight|github-markdown|dompurify' BefoldApp/package.json
```

`package.json` の記録と同梱ファイルの実バージョンが一致するか確認する。

## 2. 最新版・脆弱性を調べる

- WebSearch で各ライブラリの最新安定版と、同梱版に該当する CVE / GHSA を調べる。
- `viewer.html` の初期化（`markdownit({ html: true, linkify: true, typographer: true })`、
  mermaid の `securityLevel`）と突き合わせ、該当 CVE が実際に発火する設定かを判定する。
- DOMPurify は `md.render()` 出力の innerHTML 挿入前サニタイズとして使われており（CSP が
  `script-src 'unsafe-inline'` のため唯一の XSS 防御）、XSS バイパス系 CVE は特に優先して確認する。

## 3. 報告

ライブラリごとに「同梱版 / 最新版 / 該当 CVE / 更新推奨度」を報告する。
CVE がオプション依存で発火する場合は、更新に加えて設定側の対策も添える。
版ずれも脆弱性もなければ「✅ 同梱依存は最新・既知脆弱性なし」と報告する。
