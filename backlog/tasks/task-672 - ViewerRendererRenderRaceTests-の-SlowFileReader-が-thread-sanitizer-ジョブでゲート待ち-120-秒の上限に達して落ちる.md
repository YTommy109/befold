---
id: TASK-672
title: >-
  ViewerRendererRenderRaceTests の SlowFileReader が thread-sanitizer ジョブでゲート待ち
  120 秒の上限に達して落ちる
status: To Do
assignee: []
created_date: '2026-10-06 02:54'
labels:
  - bug
  - test
dependencies: []
references:
  - TASK-665
  - TASK-629
priority: medium
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-10-06、main push（PR #713 のマージコミット 0807c484）の CI run 37401520728 で thread-sanitizer ジョブだけが落ちた。`ViewerRendererRenderRaceTests.swift:251` で「SlowFileReader.readData: 同期待機が 120.0 秒で上限に達した（解放されないまま協調スレッドを塞いでいる）」が 1 件記録された（テスト名は «unknown» で、SlowFileReader を使う 3 テストのどれかは特定できていない）。プロセスは死んでおらず、総括行「Test run with 1997 tests in 329 suites failed ... with 1 issue」が出ている。DEADLYSIGNAL / SEGV は 0 件で、TASK-629（SEGV でプロセスごと落ちる）とは別の障害。同系統は TASK-665（並列時のゲート待ち上限超過。別テストで async の境界へ移して解消済み）。同じ run では全体が 363 秒かかり、多くのテストが 360 秒前後で完了しており、TSan 下の極端な混雑だった。同じ run の build-and-test（default / strict）は pass で、PR #713 は Swift に触れていない。未確認: 原因が混雑だけか（ゲートが塞ぐ協調スレッドが待ち先の進行を止めていないか）、再現率、TSan でしか出ないのか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 落ちたテストがどれかと、上限超過の条件（混雑だけか、塞いだ協調スレッドが待ち先の進行を止めているか）を実測で特定している
- [ ] #2 ゲートの上限を延ばす形ではなく、待ちの構造（TASK-665 と同じく async の境界へ移す等）で直っている
- [ ] #3 swift test --sanitize=thread を同一ツリーで複数回まわし、当該テストが再発しないことを実測している
<!-- AC:END -->
