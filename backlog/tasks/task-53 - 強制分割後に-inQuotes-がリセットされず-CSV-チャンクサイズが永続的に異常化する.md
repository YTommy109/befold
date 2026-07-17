---
id: TASK-53
title: 強制分割後に inQuotes がリセットされず CSV チャンクサイズが永続的に異常化する
status: To Do
assignee: []
created_date: '2026-07-17 11:50'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。CSV ファイルの最初のフィールドに閉じられない二重引用符がある場合、強制分割後に inQuotes=false へのリセットがないため以降のすべてのチャンクが 1000 行ではなく maxChunkBytes (~1MB) 単位になり復帰しない。行数表示も不正確になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 強制分割後に inQuotes 状態が適切にリセットされる
- [ ] #2 不均衡な引用符を含む CSV で後続チャンクが通常の行数ベース分割に復帰する
- [ ] #3 不均衡クォートからの復帰をテストするケースがある
<!-- AC:END -->
