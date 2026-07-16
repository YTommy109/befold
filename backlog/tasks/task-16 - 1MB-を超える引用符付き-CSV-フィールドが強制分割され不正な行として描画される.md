---
id: TASK-16
title: 1MB を超える引用符付き CSV フィールドが強制分割され不正な行として描画される
status: To Do
assignee: []
created_date: '2026-07-16 00:55'
updated_date: '2026-07-16 03:44'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/197'
priority: medium
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
引用符付きフィールドが maxChunkBytes（1MB）を超える CSV 行は、LineChunkReader が引用符状態を維持したまま強制分割し inQuotes = false にリセットする。JS 側 parseCsv はチャンクをまたぐ状態を持たないため、1 つの論理行が 2 つの不正な行として描画される。トリガーの現実性は要判断。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 挙動が確認するテストが存在するか、既知の制限として設計ドキュメントに明記されている
<!-- AC:END -->
