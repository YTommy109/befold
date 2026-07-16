---
id: TASK-29.4
title: ViewerStore を NormalizedTextCache ベースに統合する
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
labels: []
dependencies:
  - TASK-29.2
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore の computeLoad / LoadOutcome / apply() を NormalizedTextCache + StringChunkReader ベースに書き換える。textCache プロパティの追加、ChunkedReaderFactory シグネチャ変更、同一内容スキップ（contentHash）の実装を含む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 computeLoad が NormalizedTextCache を生成して StringChunkReader に渡す
- [ ] #2 textCache プロパティにキャッシュが保持される
- [ ] #3 同一 dataHash の場合に contentRevision が増分されない（TASK-23 解消）
- [ ] #4 ChunkedReaderFactory のシグネチャが (NormalizedTextCache, FileType) に変更される
- [ ] #5 既存の ViewerStoreTests / ViewerStoreChunkTests が新シグネチャで通る
<!-- AC:END -->
