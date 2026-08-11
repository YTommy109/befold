---
id: TASK-432.5
title: 手動ベンダリングを npm 依存へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:57'
updated_date: '2026-08-11 22:17'
labels: []
dependencies:
  - TASK-432.1
parent_task_id: TASK-432
priority: low
type: chore
ordinal: 112500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
バンドル基盤ができた後、手動でコミットしているベンダーライブラリを npm 依存からのバンドルへ移す。

## 現状（実測）

`BefoldApp/BefoldKit/Resources/` にミニファイド済み成果物を直接コミットしている。生成手順はリポジトリ内に無い。

| ファイル | サイズ | バージョン | package.json への記録 |
|---|---|---|---|
| `mermaid.min.js` | 3.2 MB | 11.15.0 | **無し** |
| `highlight.min.js` | 124 KB | 11.11.1 | あり |
| `markdown-it.min.js` | 121 KB | 14.2.0 | あり |
| `dompurify.min.js` | 28 KB | 3.4.12 | あり |
| `github-markdown.css` | 30 KB | 5.9.0 | あり |
| `github.css` / `github-dark.css` | 各 2.1 KB | highlight.js のテーマと推定（**未確認**） | — |

バージョンの正は `BefoldApp/package.json` の devDependencies という設計になっているが、mermaid だけ記録が無い。唯一 mermaid の版を持つのは `BefoldKit/Resources/THIRD_PARTY_LICENSES.md:11-15` の表。

## 扱いを分けること

- **mermaid は特別扱いが要る。** 3.2 MB を遅延ロードする設計（`viewer-main.js:605-608`）を壊さないため、メインバンドルには入れず独立チャンクとして出力する必要がある。
- **`github.css` / `github-dark.css` の出所が未確認。** ファイルにバナーが無く `THIRD_PARTY_LICENSES.md` にも個別項目が無い。npm 化の前に出所を確定させること。
- **`THIRD_PARTY_LICENSES.md` の更新経路。** npm 依存から自動生成する形にできるか検討する。現在は手書きの表で、`OSSLicensesView.swift:11` がこのファイルを読んでアプリ内に表示している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ベンダーライブラリが npm 依存からバンドルされ、手動コミットされたミニファイド成果物が不要になっている（mermaid を除く）
- [x] #2 mermaid が独立チャンクとして出力され、遅延ロードが維持されている
- [x] #3 github.css / github-dark.css の出所が確定し、THIRD_PARTY_LICENSES.md に記載されている
- [x] #4 THIRD_PARTY_LICENSES.md の内容が実際の依存と一致しており、ズレたら検出できる
- [x] #5 アプリ内の OSS ライセンス表示が壊れていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. mermaid を devDependencies へ追加（11.15.0）し、mermaid 専用 esbuild エントリ（viewer-src/mermaid-entry.js）から mermaid-bundle.js を IIFE で出力する。遅延ロードの script src を差し替える。
2. markdown-it / highlight.js / DOMPurify を viewer-src から import し、viewer-bundle.js に取り込む。viewer.html の 3 つの <script> と Resources の *.min.js を削除する。
3. github-markdown.css / github.css / github-dark.css は npm から生成コピーする build:viewer-css を追加（実測: hljs テーマ 2 件は 11.11.1 の styles/ とバイト一致、github-markdown.css はバナー 1 行のみ差分）。
4. THIRD_PARTY_LICENSES.md の版表を package.json / 実インストール版と突き合わせる検査を scripts/vendored-deps-versions.sh の後継として用意し、CI に追加する。
5. Package.swift のリソース列挙・viewer-src/README.md・.claude/commands/check-vendored-deps.md を追随させる。
6. npm test / build 再現性（check:viewer-bundle）/ swift build で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

- `viewer-src/vendor.js` を新設し、markdown-it / highlight.js（common ビルド）/ DOMPurify を npm から import する取り込み口を 1 箇所に閉じた。viewer.html の 3 つの `<script>` と Resources の 3 つの `*.min.js` を削除。読み込む script は viewer-bundle.js の 1 本だけになった。
- mermaid は npm の `dist/mermaid.min.js` をコピーする形にした（`scripts/copy-viewer-vendor.mjs`）。バンドルへ取り込まず遅延ロードを維持する。CSS 3 種も同スクリプトでコピーし、先頭に `名前 v版 | ライセンス | URL` のバナーを付ける。
- `scripts/check-third-party-licenses.mjs` を追加。package.json の指定版・node_modules の実インストール版・THIRD_PARTY_LICENSES.md の表の三者一致と、ライセンス表記（SPDX 集合）の一致を検査する。CI（js-test ジョブ）に追加。ルートの `scripts/vendored-deps-versions.sh` はこれを呼ぶ入口に置き換えた（同梱ファイルからバナーを grep する推定は不要になった）。

## 設計上の判断

- **markdown-it 未ロードの縮退経路を削除した。** バンドル同梱で「未ロード」が起こり得なくなったため、`_mmdInitMarkdown()` を廃してモジュール評価時の `buildMarkdownRenderer()` 1 回に畳み、`markdownRenderer()` が undefined を返さない形にした。render / appendChunk の `if (!md)` 分岐と `_renderMarkdown` の bool 戻り値も不要になり削除。
- **バンドルは minify しない。** `ViewerBridgeContractTests` が成果物のソーステキストを読んで契約を照合しているため。サイズは 78.5KB → 783KB（minify すれば 367KB）。従来はここに min 済みベンダー 273KB が別ファイルで加わっていたので、実効の増分は約 430KB。
- **契約テストを引数名照合から引数個数照合へ変えた。** ベンダーを同じ IIFE へ入れた結果、esbuild が名前衝突を避けて仮引数を改名する（`appendChunk(text, …)` → `appendChunk(text3, …)`）。契約は関数名と引数の個数であって内部識別子ではないため、`definesFunction(_:_:parameterCount:)` で照合する形にした。名前で照合したままだと無関係な依存追加で落ちる。
- **github.css / github-dark.css の出所を実測で確定した。** highlight.js@11.11.1 の `styles/` とバイト単位で一致（`diff -q` で IDENTICAL）。github-markdown.css は npm 版との差がバナー 1 行のみだった。highlight.min.js は common ビルド（36 言語）と一致（listLanguages の集合が完全一致）。

## 副産物

hljs 付きでソース表示をテストするようになった結果、ハイライトの span でパス文字列が割れると注釈されない既存不具合が表面化し TASK-455 として起票した。従来の jest ハーネスは `window.hljs` を注入しておらず、ソース表示が常に非ハイライトだったためテストから見えていなかった。

## 検証（実測）

- `npx jest`: 417 passed / 6 suites
- `swift test`: 1427 tests in 211 suites passed
- `swift build` / `xcodebuild build -scheme befold`: 成功（xcodegen generate 済み）
- `swift scripts/webview-smoke.swift`: PASS。実 WKWebView で mermaid 遅延ロード（svg）・markdown-it + DOMPurify 描画・highlight.js のハイライト・CSP のブロックを確認（highlight.js の確認ステップを追加した）
- `npm run lint:viewer` / `check:viewer-cycles` / `typecheck:viewer`: いずれも 0 件
- `scripts/vendored-deps-versions.sh`: OK。表の版を 11.14.0 に書き換えると `ERROR: Mermaid: … 11.14.0 と実際の 11.15.0 が食い違う` で非ゼロ終了することを実測で確認
- swiftlint: 69 件（触れたファイルに新規指摘なし）
- markdownlint-cli2: 0 件
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
手動コミットしていたベンダー 3 種（markdown-it / highlight.js / DOMPurify）を npm 依存として viewer-bundle.js に取り込み、mermaid とベンダー CSS は npm からのコピー生成物にした。版の正は package.json の devDependencies に一本化し、THIRD_PARTY_LICENSES.md とのずれを検出する検査を CI に追加した。jest 417 件・swift test 1427 件・実 WKWebView のスモークテスト（mermaid 遅延ロード / markdown-it / highlight.js / CSP）で検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
