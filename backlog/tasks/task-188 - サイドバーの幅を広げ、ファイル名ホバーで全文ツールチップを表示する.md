---
id: TASK-188
title: サイドバーの幅を広げ、ファイル名ホバーで全文ツールチップを表示する
status: To Do
assignee: []
created_date: '2026-07-28 14:25'
labels: []
dependencies: []
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバー（FileListView）の最小幅と初期（デフォルト）幅を現状より少し広げる。また、ファイル名が省略表示（truncation）されている場合でも、行のホバーで省略なしの完全なファイル名をツールチップ表示できるようにする。狭いサイドバーで長いファイル名が読めない問題を緩和する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーの初期幅が現状より広くなる（初回表示・記憶がない場合のデフォルト）
- [ ] #2 サイドバーの最小幅が現状より広がり、極端に狭くできない
- [ ] #3 ファイル名行にホバーすると、省略なしの完全なファイル名がツールチップ（help)で表示される
- [ ] #4 ウィンドウ単位のサイドバー幅記憶（既存挙動）が壊れない
<!-- AC:END -->
