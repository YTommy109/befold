---
id: TASK-52
title: snappedToCharacterBoundary が String.endIndex を受け取ると境界外アクセスでクラッシュする
status: To Do
assignee: []
created_date: '2026-07-17 11:50'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。advanceByLines または advanceRespectingQuotes が累積バイト数 == maxChunkBytes のとき String.endIndex を snappedToCharacterBoundary に渡しうる。utf8View[endIndex] は境界外アクセスとなり、debug ビルドではクラッシュ、release ビルドでは不正バイトを読んで分割位置が壊れコンテンツが欠落する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 snappedToCharacterBoundary が endIndex を受け取った場合に安全に処理される
- [ ] #2 debug ビルドでクラッシュしない
- [ ] #3 累積バイト数がちょうど maxChunkBytes に一致するケースのテストがある
<!-- AC:END -->
