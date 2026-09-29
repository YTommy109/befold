---
id: TASK-662.1
title: CI の build-and-test で swift test を 2 回直列に回している分を並列ジョブへ分ける
status: To Do
assignee: []
created_date: '2026-09-29 04:29'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: high
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`.github/workflows/ci.yml` の build-and-test は、通常の `swift test` のあとに `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 付きの `swift test` をもう 1 周同じジョブで回している。手元で 36 秒 + 40 秒、CI では 1 周 136 秒規模の実測がある（`BefoldTestSupport/Waiting.swift` の doc）ため、PR のクリティカルパスが 1 周分まるごと伸びている。

プール幅 1 のランは TASK-424 / 427 / 516 で 3 度再発を捕まえた検知なので、PR から外す（nightly へ移す）のではなく、検知を保ったまま待ち時間だけ消す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 プール幅 1 のランが通常ランと並列に走る（別ジョブまたは matrix）
- [ ] #2 プール幅 1 のランは引き続き PR で走り、落ちれば PR が落ちる
- [ ] #3 変更前後の PR の build-and-test 所要時間（ジョブ開始から両ラン完了まで）を Notes に記録している
<!-- AC:END -->
