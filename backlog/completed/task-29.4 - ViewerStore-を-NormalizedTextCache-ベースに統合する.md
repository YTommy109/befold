---
id: TASK-29.4
title: ViewerStore を NormalizedTextCache ベースに統合する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:46'
labels: []
dependencies:
  - TASK-29.2
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
priority: high
ordinal: 5
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore の computeLoad / LoadOutcome / apply() を NormalizedTextCache + StringChunkReader ベースに書き換える。textCache プロパティの追加、ChunkedReaderFactory シグネチャ変更、同一内容スキップ（contentHash）の実装を含む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 computeLoad が NormalizedTextCache を生成して StringChunkReader に渡す
- [x] #2 textCache プロパティにキャッシュが保持される
- [x] #3 同一 dataHash の場合に contentRevision が増分されない（TASK-23 解消）
- [x] #4 ChunkedReaderFactory のシグネチャが (NormalizedTextCache, FileType) に変更される
- [x] #5 既存の ViewerStoreTests / ViewerStoreChunkTests が新シグネチャで通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装計画 Task 3 に準拠:
1. ViewerStore を読み、現行の computeLoad / LoadOutcome / apply / ChunkedReaderFactory を把握
2. ChunkedReaderFactory シグネチャ変更、textCache / contentHash プロパティ追加
3. LoadOutcome にキャッシュを追加
4. computeLoad を NormalizedTextCache ベースに書き換え
5. apply() に同一内容スキップを追加
6. close() でキャッシュ解放
7. ViewerStoreTests のファクトリシグネチャ更新
8. テスト全通し確認
9. コミット
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore の computeLoad を Data→NormalizedTextCache→StringChunkReader パイプラインに刷新。ChunkedReaderFactory を (URL, FileType) から (NormalizedTextCache, FileType) に変更。dataHash による同一内容スキップを実装。行指向ファイル 100MB / 非行指向 10MB のサイズ上限を適用。全 366 テスト通過。コミット 2e73a5a。
<!-- SECTION:FINAL_SUMMARY:END -->
