---
id: TASK-55
title: advanceByLines と advanceRespectingQuotes の行境界ロジック重複を解消する
status: To Do
assignee: []
created_date: '2026-07-17 11:50'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。両メソッドが同一の行末計算・scanLine 追跡・linesConsumed カウントロジックを持っている。内部のスキャン方式（CSV のバイト単位 vs 非 CSV の行単位）と強制分割トリガーだけが異なる。変更時に 2 箇所の同期が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 行境界ルックアップロジックが共通化されている
- [ ] #2 既存の StringChunkReader テストがすべてパスする
<!-- AC:END -->
