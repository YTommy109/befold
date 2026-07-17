---
id: TASK-46
title: StringChunkReader の強制分割が UTF-8 マルチバイト境界と CSV クォート状態を壊す
status: To Do
assignee: []
created_date: '2026-07-17 05:09'
updated_date: '2026-07-17 05:21'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 2100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
maxChunkBytes での強制分割時に2つの問題がある: (1) utf8View.index(after:) でバイト単位に進めるため UTF-8 継続バイト上で分割しうる（旧コードは行境界分割で文字境界を保証していた）。(2) 分割後に inQuotes が無条件に false にリセットされ、クォート内の複数行 CSV フィールドが正しくチャンクされない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 強制分割が UTF-8 文字境界を尊重し、マルチバイト文字の途中で分割しない
- [ ] #2 強制分割後も inQuotes 状態が維持され、クォート内複数行フィールドが正しくチャンクされる
- [ ] #3 1MB超の単一行日本語テキストでの強制分割テストが通る
<!-- AC:END -->
