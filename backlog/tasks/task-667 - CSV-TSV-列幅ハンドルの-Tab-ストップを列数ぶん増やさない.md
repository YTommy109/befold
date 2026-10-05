---
id: TASK-667
title: CSV/TSV 列幅ハンドルの Tab ストップを列数ぶん増やさない
status: To Do
assignee: []
created_date: '2026-10-05 22:50'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
priority: low
ordinal: 852000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708 の列幅ハンドルは各ヘッダーに `tabIndex = 0` の `role="separator"` を置くため、100 列の CSV では Tab が 100 回ハンドルに止まる。実機の VoiceOver での挙動は未確認。`aria-valuemax` も付いていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ハンドルの Tab ストップが表全体で 1 つ（roving tabindex など）になり、左右キーで列間を移動できる、または現状維持の理由が Notes に残っている
- [ ] #2 aria-valuemax を付けるか付けないかが決まっている
- [ ] #3 選んだ挙動をテストで固定している
<!-- AC:END -->
