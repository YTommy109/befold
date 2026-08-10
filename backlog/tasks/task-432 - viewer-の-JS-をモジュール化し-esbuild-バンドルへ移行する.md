---
id: TASK-432
title: viewer の JS をモジュール化し esbuild バンドルへ移行する
status: To Do
assignee: []
created_date: '2026-08-10 12:55'
labels: []
dependencies: []
documentation:
  - docs/adr/0005-bundle-viewer-js-with-esbuild.md
priority: medium
type: chore
ordinal: 507550
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/BefoldKit/Resources/` の自前 JS（`viewer-main.js` 1,873 行 + `viewer.js` 939 行）はモジュールシステムを持たず、すべての識別子が真のグローバルで、ファイル間の依存は `viewer.html:56-60` のスクリプト記述順だけで解決している。分割軸も責務ではなくテスト可能性で引かれており、TASK-414 の乖離（`appendChunk` と `render` の表示モード判定）を生んだ。

`file://` 読み込み（`BefoldRenderKit/ViewerRenderer.swift:253-257`）と CSP `script-src self`（`viewer.html:17`）の下ではネイティブ ES モジュールが使えないため、モジュール境界を得る現実的な経路はバンドラのみ。判断の全体と却下案は `docs/adr/0005-bundle-viewer-js-with-esbuild.md`（decision-5）に記録した。

このタスクは ADR 0005 の実行を段階に分けて進める親タスク。TASK-420（viewer-main.js を責務ごとに分割）はサブタスクへ統合済み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer の自前 JS が esbuild のバンドル成果物として .app へ同梱されている
- [ ] #2 コミットされた成果物とソースのズレが CI で検出される
- [ ] #3 mermaid.min.js の遅延ロードが維持されている（バンドルに取り込まれていない）
- [ ] #4 viewer-main が責務ごとのモジュールへ分割されている
- [ ] #5 既存の jest テストと ViewerBridgeContractTests が通る
<!-- AC:END -->
