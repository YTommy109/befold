---
id: TASK-664
title: CI で Distributed Notification の配送待ちテスト 2 件が同時にタイムアウトする（再発）
status: To Do
assignee: []
created_date: '2026-09-29 05:22'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 865000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DistributedAckWaiterIntegrationTests「待ち受け開始後・wait 呼び出し前に届いた ACK も観測される」と CLIRequestWireIntegrationTests「全オプション付きの要求が実際の Distributed Notification を通って復元できる」が、同じ CI ジョブ内で**どちらも 89.6 秒でタイムアウト**した（2026-09-29、PR #703 run 36525076672 の build-and-test (strict)。同じ run の default ジョブは緑）。

TASK-622 の Notes に「同じ再実行で 1 回落ちた。配送経路が別なので範囲外、再発するなら別タスク」と記録があり、今回が 2 回目の観測。2 件が同時刻に同じ待ち時間で落ちているので、個々のテストの待ち方ではなく、ランナー上でプロセス間通知の配送そのものが止まった可能性が高い（未確認: 配送が止まったのか、受信側の runloop / MainActor が回っていないのかは切り分けていない。ログの完了時刻の並びと、受信コールバックの配送キューを調べれば分かる）。

PR #703（TASK-662.2）は befoldCLITests にもこの 2 テストにも触れていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 失敗 2 回分の CI ログから、配送が止まったのか受信側が回っていないのかを切り分けて Notes に記録している
- [ ] #2 原因に応じて、同じ形で落ちない構造（受信の配送先・待ち方）へ直している、または再現できない場合はその根拠を記録している
<!-- AC:END -->
