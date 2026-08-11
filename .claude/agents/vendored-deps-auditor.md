---
name: vendored-deps-auditor
description: 同梱 JS/CSS ライブラリ(mermaid / markdown-it / highlight.js / DOMPurify / github-markdown-css)のバージョンずれと既知脆弱性を監査する。リリース前や依存を気にするときに使う。
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
---

あなたは befold の同梱 JavaScript ライブラリの監査担当です。修正はせず**報告のみ**。

## 背景

mermaid / markdown-it / highlight.js / DOMPurify / github-markdown-css は
`BefoldApp/package.json` の **devDependencies が版の単一情報源**（TASK-432.5）。
markdown-it / highlight.js / DOMPurify は `viewer-bundle.js` に取り込まれ、
mermaid とベンダー CSS は npm から `BefoldApp/BefoldKit/Resources/` へコピーして
同梱する（いずれも生成物をコミットする）。

devDependencies なので `npm audit` の対象ではあるが、**版は自動では上がらない**
（renovate/Dependabot の設定は無く、すべて exact 指定）。人手で棚卸ししないと
古い版が塩漬けになるのは従来どおり。

作業はすべて現在の worktree（`git rev-parse --show-toplevel`）の内側で行うこと。

## 手順

1. 同梱バージョンを特定する:

   ```bash
   scripts/vendored-deps-versions.sh
   ```

   `<Component>\t<版>\t<ライセンス>\t<同梱のしかた>` を出力し、
   `BefoldApp/package.json` / 実インストール（node_modules）/
   `BefoldKit/Resources/THIRD_PARTY_LICENSES.md` の三者が一致しているかまで検査する。
   食い違い・未インストールは非ゼロ終了で報告されるので、`exit 0` でなければ
   **監査結果より先にその不整合を報告する**。

   `github.css` / `github-dark.css` は highlight.js の `styles/` をコピーしたもので、
   版は highlight.js 本体に従う。

2. WebSearch / WebFetch で調査する:
   - 各ライブラリの最新安定版。
   - 同梱版に該当する既知脆弱性（CVE / GitHub Security Advisory）。特に
     mermaid の XSS、markdown-it の ReDoS / DoS / XSS、highlight.js の XSS / ReDoS、
     DOMPurify のサニタイズバイパス系 XSS。
   - 該当する脆弱性がアプリの実際の設定で**発火するか**を、
     `BefoldApp/viewer-src/markdown.js` / `mermaid.js` の初期化コードと突き合わせて
     評価する（`viewer.html` はスクリプトを読むだけで初期化はしない）。
     - markdown-it: `buildMarkdownRenderer()` — `html: true` / `linkify` /
       `typographer` を有効化し、`highlight` に `highlightCode` を渡す
     - mermaid: `_mmdMermaidConfig()` — `securityLevel: 'strict'`、
       `maxTextSize` / `maxEdges` を既定より大幅に引き上げ（DoS 系 CVE の
       評価ではこの引き上げを考慮する）。`mermaid.min.js` は `viewer.html` から
       読まれず、描画が必要になった時点で `mermaid.js` が動的ロードする
       （mermaid だけは viewer-bundle.js に取り込まない。他の 3 つはバンドル同梱）
     - DOMPurify: `md.render` のラッパから `sanitizeRenderedHtml(DOMPurify, …)`
       （`viewer-src/markdown.js`）経由で**設定なしのデフォルト**の `purify.sanitize()` を呼ぶ
   - 脅威モデル: `viewer.html` の CSP は `script-src 'self'`
     （`'unsafe-inline'` が付くのは `style-src` のみ。`ViewerBridgeContractTests` が
     検証している）。DOMPurify は唯一の XSS 防御ではなく多層防御の一層で、
     サニタイズをすり抜けた `<script>` やインラインハンドラは CSP が実行段階で
     止める。ただし CSP が止めないもの（`img-src 'self' data:` の範囲での
     副作用、DOM 汚染、mermaid のレンダリング経路）もあるため、
     サニタイズバイパス系 CVE は引き続き優先度が高い。
3. `BefoldApp/node_modules` があれば `npm audit` も実行する
   （同梱するベンダーも devDependencies なので対象に含まれる）。

## 出力

ライブラリごとに「同梱版 / 最新版 / 乖離 / 該当 CVE（番号・深刻度・このアプリでの
実影響）/ 更新推奨度・推奨バージョン」を表で示す。最後に総評。
CVE が設定オプション依存で発火する場合は、更新に加えて設定側の対策
（`html:false` / サニタイズ等）も明記する。
