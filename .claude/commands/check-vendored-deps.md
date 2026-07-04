# /check-vendored-deps — 同梱 JS ライブラリの棚卸し

`mermaid.min.js` / `markdown-it.min.js` / `highlight.min.js`(+ テーマ CSS `github.css` / `github-dark.css`)は手動ベンダリングで Dependabot の監視外。
版ずれと既知脆弱性を確認する。詳細な監査が必要なら `vendored-deps-auditor`
サブエージェントに委譲してよい。

## 1. 同梱バージョンを特定する

```bash
head -1 MmdviewApp/mmdview/Resources/markdown-it.min.js
grep -o '"version":"[0-9.]*"' MmdviewApp/mmdview/Resources/mermaid.min.js | head -1
grep -o 'versionString="[0-9.]*"' MmdviewApp/mmdview/Resources/highlight.min.js | head -1
grep -E 'markdown-it|mermaid|highlight' MmdviewApp/package.json
```

`package.json` の記録と同梱ファイルの実バージョンが一致するか確認する。

## 2. 最新版・脆弱性を調べる

- WebSearch で各ライブラリの最新安定版と、同梱版に該当する CVE / GHSA を調べる。
- `viewer.html` の初期化（`markdownit({ html: true, linkify: true, typographer: true })`、
  mermaid の `securityLevel`）と突き合わせ、該当 CVE が実際に発火する設定かを判定する。

## 3. 報告

ライブラリごとに「同梱版 / 最新版 / 該当 CVE / 更新推奨度」を報告する。
CVE がオプション依存で発火する場合は、更新に加えて設定側の対策も添える。
版ずれも脆弱性もなければ「✅ 同梱依存は最新・既知脆弱性なし」と報告する。
