---
id: TASK-664
title: CI で Distributed Notification の配送待ちテスト 2 件が同時にタイムアウトする（再発）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 05:22'
updated_date: '2026-09-29 06:28'
labels: []
dependencies: []
priority: high
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
- [x] #1 失敗 2 回分の CI ログから、配送が止まったのか受信側が回っていないのかを切り分けて Notes に記録している
- [x] #2 原因に応じて、同じ形で落ちない構造（受信の配送先・待ち方）へ直している、または再現できない場合はその根拠を記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CI の swift test を befoldCLITests とそれ以外の 2 プロセスに分ける（build-and-test 両レッグと thread-sanitizer）
2. 受信側をメイン以外へ移す案は採らない: 停滞はテストの同居でしか起きず、本番コードを変える理由がない
3. PR #703（3/3 で strict が落ちた状態）に載せて strict が緑になることを実測する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-09-29 追加実測（TASK-662.2 / PR #703）:
- #703 の strict は 3/3 で同じ 2 件だけ落ちた（run 36525076672 attempt 1〜3。default は 3/3 緑）。#702（変更前）の strict は 2/2 緑
- #703 から変更を 3 グループのどれか 1 つだけ戻した使い捨て PR #704 / #705 / #706 は、strict がすべて緑（run 36526878800 / 36527059256 / 36527243499）。**特定のテストが原因ではなく、実行順・タイミングがずれたことで顕在化した**
- テスト完了時刻を 10 秒刻みで数えると、失敗した回は約 30〜100 秒にほとんど完了が無く（81 / 10 / 13 / 8 / 2 件）、100〜110 秒で 879 件が一斉に完了している。メインキューが約 70 秒詰まっている
- ACK の 2 件は失敗時に 85〜90 秒で落ちる（予算 60 秒なので開始は 25〜30 秒）＝停滞の始まりに開始し、停滞が予算より長く続いた。#702 の緑の回は 2 件とも 24.77 秒に同時に通っており、最初の停滞が解けた瞬間にまとめて配送されていた（配送は常にメインランループの一巡待ち）
- 手元では再現しない: 手元のツールチェーンは befoldCLITests（72 件）を別プロセスで回すため、befoldTests の停滞と重ならない。CI は 2089 件を 1 プロセスで回している
結論: 配送はメインランループ経由（TASK-327 の実測どおり）で、同じプロセスの @MainActor テストがメインを予算より長く塞ぐと落ちる。予算の延長ではなく、befoldTests の停滞と切り離す形（別プロセスで回す等）が要る。PR #703 のマージはこのタスクに塞がれている

2026-09-29 対処（706cd963）:
- AC#1 の切り分けは上の追加実測のとおり。配送は止まっていない。受信側のメインランループが、同じプロセスの @MainActor テストに約 70 秒塞がれている
- 単純化の検討: 受信をメイン以外のランループへ移す案は採らない。この停滞はテストの同居でしか起きず、本番コードを変える理由がない。実配送に依存するテストは befoldCLITests にしか無い（befoldTests の CLIRequestDeduplicatorTests は純粋ロジック）
- ci.yml の build-and-test（両レッグ）と thread-sanitizer を、swift test --skip befoldCLITests と --filter befoldCLITests の 2 プロセスに分けた。手元の実測は 2017 + 72 = 2089 件で、CI が 1 プロセスで回していた件数と一致する
- 検証: PR #703 の strict は変更前 3/3 で赤、変更後は run 36530311972 の attempt 1 と 2 で 2/2 緑（befoldTests 68.0 秒 / 84.4 秒、befoldCLITests 0.79 秒 / 0.94 秒）。befoldTests 側のメインの停滞は残るが、ACK 待ちには届かなくなった
- thread-sanitizer は PR では回らないため未実測。main への push 後の実行で確認する
- 現在仕様の文書（native-app-design.md）は CI 構成を記述していないため、更新不要
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI の swift test を befoldCLITests とそれ以外の 2 プロセスに分けた。befoldTests の @MainActor テストがメインランループを塞いでも、Distributed Notification の ACK 待ちがタイムアウトしなくなった。変更前 3/3 で赤だった PR #703 の strict レッグが、変更後 2/2 で緑（run 36530311972）。
<!-- SECTION:FINAL_SUMMARY:END -->
