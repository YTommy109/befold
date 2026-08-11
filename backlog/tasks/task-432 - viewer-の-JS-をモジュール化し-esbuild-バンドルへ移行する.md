---
id: TASK-432
title: viewer の JS をモジュール化し esbuild バンドルへ移行する
status: Done
assignee: []
created_date: '2026-08-10 12:55'
updated_date: '2026-08-11 22:34'
labels: []
dependencies: []
documentation:
  - docs/adr/0005-bundle-viewer-js-with-esbuild.md
priority: medium
type: chore
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/BefoldKit/Resources/` の自前 JS（`viewer-main.js` 1,873 行 + `viewer.js` 939 行）はモジュールシステムを持たず、すべての識別子が真のグローバルで、ファイル間の依存は `viewer.html:56-60` のスクリプト記述順だけで解決している。分割軸も責務ではなくテスト可能性で引かれており、TASK-414 の乖離（`appendChunk` と `render` の表示モード判定）を生んだ。

`file://` 読み込み（`BefoldRenderKit/ViewerRenderer.swift:253-257`）と CSP `script-src self`（`viewer.html:17`）の下ではネイティブ ES モジュールが使えないため、モジュール境界を得る現実的な経路はバンドラのみ。判断の全体と却下案は `docs/adr/0005-bundle-viewer-js-with-esbuild.md`（decision-5）に記録した。

このタスクは ADR 0005 の実行を段階に分けて進める親タスク。TASK-420（viewer-main.js を責務ごとに分割）はサブタスクへ統合済み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 viewer の自前 JS が esbuild のバンドル成果物として .app へ同梱されている
- [x] #2 コミットされた成果物とソースのズレが CI で検出される
- [x] #3 mermaid.min.js の遅延ロードが維持されている（バンドルに取り込まれていない）
- [x] #4 viewer-main が責務ごとのモジュールへ分割されている
- [x] #5 既存の jest テストと ViewerBridgeContractTests が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
サブタスク 5 件（432.1〜432.5）の完了をもって親を締める。個別の実装内容・判断は各サブタスクの Notes にある。ここには親の Acceptance Criteria に対する検証証跡だけを残す。

## AC ごとの証跡（実測 2026-08-12、rebase 後の origin/main + 本ブランチ）

- **#1 バンドル成果物として .app へ同梱**: `xcodebuild build -scheme befold` 成功。生成された
  `befold.app/Contents/Frameworks/BefoldKit.framework/Versions/A/Resources/` の中身は
  `viewer-bundle.js`(783KB) / `mermaid.min.js`(3.2MB) / CSS 3 種 / `viewer.html` /
  `THIRD_PARTY_LICENSES.md` のみ。移行前の `viewer.js` / `viewer-main.js` と、
  ベンダー 3 種の `*.min.js` はいずれも .app に存在しない。
- **#2 成果物とソースのズレを CI が検出**: `.github/workflows/ci.yml` の js-test ジョブに
  `npm run check:viewer-bundle`（再ビルド + `git diff --exit-code`）がある。TASK-432.5 で
  ベンダーのコピー物（mermaid.min.js / CSS 3 種）も比較対象に加え、併せて
  `npm run check:third-party-licenses` を追加した。ローカル実行はいずれも OK。
- **#3 mermaid の遅延ロード維持**: `viewer-bundle.js` に mermaid 本体は含まれない
  （`__esbuild_esm_mermaid_nm` / `mermaidAPI` の出現 0 件）。バンドル内には
  `script.src = "mermaid.min.js"` の動的挿入だけがある。実 WKWebView での
  `swift scripts/webview-smoke.swift` が `.mmd` の SVG 描画まで到達して PASS。
- **#4 責務ごとのモジュール分割**: `viewer-src/` は 27 モジュール（.js / .ts）。循環 import は
  `npm run check:viewer-cycles` で 0 件（26 モジュールを走査）。
- **#5 jest と ViewerBridgeContractTests**: `npx jest` 417 passed / 6 suites、
  `swift test` 1429 tests in 211 suites passed（`ViewerBridgeContractTests` 11 件を含む）。

## 積み残し（別タスクへ）

- TASK-455: ソース表示でハイライトの span に割られたパス参照が注釈されない
  （432.5 でテストが本番と同じ hljs 付き経路を通るようになり表面化した既存不具合）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ADR 0005 の実行を 5 段階で完了した。viewer の自前 JS（viewer.js 939 行 + viewer-main.js 1,873 行のグローバル 2 ファイル）を viewer-src/ の 27 モジュールへ分割し、esbuild の単一 IIFE バンドルとして .app へ同梱する形へ移行。依存はスクリプト記述順ではなく import で表現され、循環は 0 件。TypeScript への段階移行の足場（tsc --noEmit / eslint no-undef）と、成果物・同梱ライセンスのズレを落とす CI 検査も入れた。ベンダーは npm 依存に一本化し、mermaid だけは遅延ロードのためバンドル外に置いている。jest 417 件・swift test 1429 件・実 WKWebView のスモークテストで検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
