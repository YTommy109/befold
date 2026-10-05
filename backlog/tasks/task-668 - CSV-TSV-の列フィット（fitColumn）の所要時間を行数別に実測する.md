---
id: TASK-668
title: CSV/TSV の列フィット（fitColumn）の所要時間を行数別に実測する
status: To Do
assignee: []
created_date: '2026-10-05 22:50'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
priority: low
ordinal: 853000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708 の `fitColumn` は読み込み済みの全行のセルをクローンして測るため、行数に比例して重くなる。PR 説明は 5,000 行超でも応答したと述べるが所要時間の記載はない。数値が無いまま上限の要否を決められない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 1,000 / 10,000 / 50,000 行程度でフィットの所要時間が実測され、Notes に数値で残っている
- [ ] #2 許容できない遅さなら対象行数の上限などの対策を入れ、許容範囲なら「不要」と結論が Notes に残っている
<!-- AC:END -->
