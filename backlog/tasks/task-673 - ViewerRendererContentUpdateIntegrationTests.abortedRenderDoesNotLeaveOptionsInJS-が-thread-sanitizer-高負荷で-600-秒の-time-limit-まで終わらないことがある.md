---
id: TASK-673
title: >-
  ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS
  が thread-sanitizer + 高負荷で 600 秒の time limit まで終わらないことがある
status: To Do
assignee: []
created_date: '2026-10-06 06:00'
updated_date: '2026-10-06 07:43'
labels:
  - bug
  - test
dependencies: []
references:
  - TASK-672
priority: medium
ordinal: 858000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-672 の修正後の検証（2026-10-06、TSan + CPU 負荷 yes 40 本 + 全体実行 6 回、ログは .tmp/t672c-C40-3.log）で、6 回中 1 回（run3）、このテストだけが `Time limit was exceeded: 600.000 seconds` で落ちた（754 秒）。他のテストは約 445 秒で pass しており、単なる全体の混雑では説明できない。「SlowFileReader.readData の同期待機が」issue は出ていない。実 WKWebView を使い、waitForWebViewLoad（isReady / entered / rendered.contentRevision の 3 つの待ち）と evaluateJavaScript を持つ唯一の SlowFileReader 利用テスト。修正前の負荷実行（3 回）ではこの失敗は出ていないが標本が小さく、TASK-672 の修正（SlowFileReader の上限なし化）由来か、元からある別の flaky かは判定できていない。修正前の負荷実行では同じ型の WKWebView 系の別の失敗（ViewerRendererOneShotIntegrationTests、`document.getElementById(diagram-wrap)` が null）も 1 回出ている。未確認: どの await で止まったか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 このテストが止まる await（waitForWebViewLoad の 3 つの待ち・evaluateJavaScript のどれか）、または SlowFileReader のゲートが開かれないままの待ちのどちらかが特定されている
- [ ] #2 TASK-674.1 を含むツリー（上限なしの waitUntilOpen のみ）と、上限付きだった TASK-672 修正前のツリーで、同じ負荷・同じ回数の発生率が比較され、上限なし化由来かどうかが判定されている
- [ ] #3 上限なし化由来なら、開け忘れ時に終わらない形（ADR 0012 の再検討条件）への対処（.timeLimit と同じ定数の自己解放など）の要否が判断され、既存の flaky ならその原因への対処が入り、同じ負荷で複数回まわして再発しないことを実測している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-674 / 674.1 との関係（2026-10-06）: (1) 674 の実測で、開け忘れは「結果を待つテストが .timeLimit まで終わらない」形で出る。本タスクの症状（600 秒で time limit、754 秒）と一致するため、原因は WKWebView の待ちでなくゲートが開かれないまま上限なしで待ち続けた可能性がある（推定、未確認）。上限付きの時代は 120 秒で issue になっていたはずの状態が、TASK-672 の上限なし化で「終わらない」に変わった、という仮説。(2) TASK-674.1 の検査（塞いではいけないスレッドでの待機）は withBlockingWork の専用 Thread 上では発火しないため、この状態は検査で捕まらない。(3) ADR 0012「再検討する条件」は『開け忘れによる終わらない run が CI で起きたら自己解放を足す』。本件は手元の TSan + 負荷での観測で CI ではないが、条件を前倒しで判断する材料になる。(4) AC#2 の比較対象を『TASK-672 の修正を含まないツリー』から『674.1 を含むツリーと上限付きだった修正前』へ更新した。
<!-- SECTION:NOTES:END -->
