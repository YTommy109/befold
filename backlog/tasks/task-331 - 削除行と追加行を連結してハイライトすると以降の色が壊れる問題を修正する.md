---
id: TASK-331
title: 削除行と追加行を連結してハイライトすると以降の色が壊れる問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
highlightedDiffLines（viewer.js:422）は hunk 内の全行のテキストを texts.join(\n) で 1 ブロックにしてから hljs にかける。GitDiffReader.wholeFileContextLines（-U1000000）によりファイル全体が単一 hunk になるため、変更行の旧版と新版が隣接し、文字列リテラル・コメント区切り・括弧の途中を編集しただけでレクサ状態が壊れてファイル残り全体が誤った色になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 文字列リテラルを書き換えた差分で、変更行より後のハイライトが通常表示と一致する
- [ ] #2 削除行群と追加行群を分けてハイライトする（もしくは同等の方法でレクサ状態の混線を防ぐ）
- [ ] #3 修正を戻すと落ちるテストがある
<!-- AC:END -->
