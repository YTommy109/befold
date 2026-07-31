---
id: TASK-234
title: 描画系の重複定義を単一情報源化する（チャンクリーダー既定・表示行数・truncatedScript・トグル文言）
status: To Do
assignee: []
created_date: '2026-07-31 09:16'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 410000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
(1) chunkedReaderFactory の既定クロージャ（StringChunkReader + ChunkBoundary）が ViewerStore.swift:150 / ViewerRenderer+OneShot.swift:96 / CLICheckCommand.swift:66 とテスト 3 箇所に完全同一で散在 — ViewerLoadPipeline.defaultChunkedReaderFactory に集約（CLI の --check が GUI とドリフトすると実害大）。(2) 表示行数の算出が ViewerStore.updateDisplayedLineCount と ViewerRenderer+OneShot.displayedLineCount に二重実装（doc コメントが「同じ規則」と明記＝ドリフト前提）— BefoldKit に共通実装を置く。ViewerStore の増分カウント最適化は維持。(3) TruncationState → truncatedScript の 3 引数手ばらしが 3 箇所 — TruncationState に script プロパティを持たせる。(4) 行番号/ブックマーク/ソース切替のトグル文言ペアが ViewerToolbarController と ViewerWindowController.validateMenuItem に重複 — ViewerCommandTitles に集約。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 4 項目それぞれの定義箇所が 1 箇所になり、既存テストが通る
- [ ] #2 QuickLook/本体/CLI の間で行数・チャンク境界の規則が共有されている
<!-- AC:END -->
