---
id: TASK-923
title: thread-sanitizer ジョブの全体実行が 10 分を超えた回に、35 件が .timeLimit で一斉に落ちる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T04:29:00Z'
updated_date: '2026-11-09T04:29:00Z'
labels:
  - ci
  - test
  - test-infra
dependencies: []
references:
  - https://github.com/YTommy109/befold/actions/runs/42405199036
  - TASK-517
  - TASK-907
priority: medium
type: bug
ordinal: 889000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
定期実行の thread-sanitizer（run 42405199036、commit 64c21ea8）で 1 本目のプロセスが 627.5 秒かかり、.timeLimit（既定 10 分、CI で上書きなし）を超えた 35 件が落ちた。残る 2 件の #expect 失敗は打ち切りの巻き添えと見られる。同じコミットの翌日の回は 476.8 秒で成功。直近の成功 19 回は 217〜558 秒で、同一コミット 38afdff0 でも 239〜541 秒とばらつくため、制限までの余裕がばらつきの中に入っている。完了が途切れた最長区間は失敗回 100 秒、成功回は最大 209 秒で、失敗回に特有の停止は見られない。TASK-517 と同じ型（.timeLimit が実行全体の壁時計を測る）の 2 件目。遅さのばらつきの原因は未特定。TSan ジョブは test-watchdog.sh を通しておらず、止まった時点の情報が残らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TSan ジョブの .timeLimit が通常のばらつきで届かない値になっている
- [ ] #2 TSan の 3 コマンドが test-watchdog.sh を通り、止まったら診断が artifact に残る
- [ ] #3 main の push または定期実行で TSan ジョブが緑になり、watchdog の誤検知が出ていないことを実測している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TSan ジョブの env に BEFOLD_TEST_TIME_LIMIT_MINUTES: 20 を設定する
2. 3 コマンドを test-watchdog.sh（--quiet-seconds 400）経由にし、診断を artifact へ保存する
3. thread-sanitizer は PR では走らないので、マージ後の main で緑と誤検知なしを確認する
<!-- SECTION:PLAN:END -->
