---
id: TASK-923
title: thread-sanitizer ジョブの全体実行が 10 分を超えた回に、35 件が .timeLimit で一斉に落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T04:29:00Z'
updated_date: '2026-11-10T00:38:00Z'
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
- [x] #1 TSan ジョブの .timeLimit が通常のばらつきで届かない値になっている
- [x] #2 TSan の 3 コマンドが test-watchdog.sh を通り、止まったら診断が artifact に残る
- [x] #3 main の push または定期実行で TSan ジョブが緑になり、watchdog の誤検知が出ていないことを実測している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TSan ジョブの env に BEFOLD_TEST_TIME_LIMIT_MINUTES: 20 を設定する
2. 3 コマンドを test-watchdog.sh（--quiet-seconds 400）経由にし、診断を artifact へ保存する
3. thread-sanitizer は PR では走らないので、マージ後の main で緑と誤検知なしを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
完了確認（2026-11-10、#784 = b118ab17 の後の main の TSan ジョブ 4 回。gh run view --log で実測）

| run | きっかけ | 1 本目のプロセス | 出力の最長の途切れ | 結果 |
|---|---|---|---|---|
| 42563999660 | push b118ab17 | 722.6 秒 | 122 秒 | 成功 |
| 42580750872 | push d83e5c68 | 527.2 秒 | 56 秒 | 成功 |
| 42614257676 | push 4b71eeb1 | 704.2 秒 | 96 秒 | 成功 |
| 42722282040 | schedule 4b71eeb1 | 814.2 秒 | 97 秒 | 成功 |

- 4 回中 3 回は旧制限 600 秒を超えた。修正前なら本件と同じ形で落ちていた。新しい制限 1200 秒までの余裕は最小で 386 秒
- watchdog の打ち切りメッセージ（test-watchdog.sh の `::error::出力が … 秒止まった`）はどのログにも無い。出力の途切れは最長 122 秒で、--quiet-seconds 400 に届いていない
- 気になる点（未調査）: 起票時の成功 19 回は 217〜558 秒だったが、今回の 4 回は 527〜814 秒で、すべて当時の最大を超えた。テストが増えたせいかランナーのばらつきかは調べていない。遅くなる傾向が続くと 1200 秒の余裕も減るので、次に TSan の打ち切りが出たら所要時間の推移から見る
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TSan ジョブの .timeLimit を BEFOLD_TEST_TIME_LIMIT_MINUTES: 20 で延ばし、3 コマンドを test-watchdog.sh（--quiet-seconds 400）経由にして、止まったときの診断を artifact に残すようにした（#784）。#784 の後の main の TSan ジョブは 4 回とも成功した。1 本目のプロセスは 527〜814 秒で、うち 3 回は旧制限の 600 秒を超えていた。watchdog の誤検知は無く、出力の途切れは最長 122 秒だった。残るリスクとして、所要時間が起票時（217〜558 秒）より長くなっている。原因は未調査で Notes に記録した。
<!-- SECTION:FINAL_SUMMARY:END -->
