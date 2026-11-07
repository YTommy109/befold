---
id: TASK-906.4
title: 印刷と PDF で CSV のセルが切り取られる
status: To Do
assignee: []
created_date: '2026-11-07T02:56:00Z'
labels: []
dependencies:
  - TASK-906.1
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: medium
type: bug
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
@media print は csv-sized も .csv-scroll も解除していない。csv-sized は従来、手動で幅を変えた後にだけ付いていたが、PR #748 ですべての CSV に付く。折り返して全文を印刷できていたセルが、切り取られたまま出力されるはず（コードからの判断、未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 印刷と PDF で、従来全文が出ていたセルが切り取られない
- [ ] #2 実際の印刷または PDF 出力で確認した結果が Notes にある
<!-- AC:END -->
