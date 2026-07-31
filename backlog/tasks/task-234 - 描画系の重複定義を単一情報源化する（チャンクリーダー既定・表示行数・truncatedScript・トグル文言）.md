---
id: TASK-234
title: 描画系の重複定義を単一情報源化する（チャンクリーダー既定・表示行数・truncatedScript・トグル文言）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:16'
updated_date: '2026-07-31 22:51'
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
- [x] #1 4 項目それぞれの定義箇所が 1 箇所になり、既存テストが通る
- [x] #2 QuickLook/本体/CLI の間で行数・チャンク境界の規則が共有されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerLoadPipeline.defaultChunkedReaderFactory を新設し、ViewerStore / loadOneShot / CLICheckCommand とテスト 3 箇所をそこへ寄せる
2. BefoldKit に DisplayedLineCount を新設し、ViewerStore の増分カウントと loadOneShot の全走査版を同じ規則に統一
3. TruncationState に script プロパティを持たせ、3 引数の手ばらし 3 箇所を撤去
4. ViewerCommandTitles を新設し、行番号/ブックマーク/ソース切替のトグル文言ペアを集約
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
4 項目とも定義箇所を 1 つにした。(1) ViewerLoadPipeline.defaultChunkedReaderFactory を新設し、GUI 本体(ViewerStore)・QuickLook 経路(loadOneShot)・CLI(--check)とテスト 3 箇所の同一クロージャを撤去。--check と GUI のチャンク境界がドリフトする余地がなくなった。(2) BefoldKit.DisplayedLineCount を新設し、ViewerStore.updateDisplayedLineCount(改行数の増分カウント)と ViewerRenderer.displayedLineCount(全走査)を count(newlines:in:) / count(of:) の 2 面から同じ規則へ統一。ViewerStore の増分カウント最適化は維持している。ViewerRenderer.displayedLineCount は削除し、テストは新設の DisplayedLineCountTests へ移設のうえ『増分版と全走査版が一致する』ケースを追加。(3) TruncationState.script を追加し、isTruncated/lineCount/failed の手ばらし 3 箇所を撤去。(4) ViewerCommandTitles を新設し、行番号・ブックマーク・ソース切替の文言ペアを ViewerWindowController.validateMenuItem と ViewerToolbarController の双方から参照する形にした。ファイル増減があるため xcodegen generate 済み。検証: swift test → 943 passed / swiftformat --lint パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
描画系の重複定義 4 項目（チャンクリーダー既定・表示行数・truncatedScript・トグル文言）をそれぞれ単一情報源へ集約した。特にチャンクリーダー既定と表示行数は本体・QuickLook・CLI の 3 ホストで共有され、ホスト間のドリフト余地がなくなった。swift test 943 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
