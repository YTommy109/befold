---
id: TASK-673
title: >-
  ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS
  が thread-sanitizer + 高負荷で 600 秒の time limit まで終わらないことがある
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-06 06:00'
updated_date: '2026-10-06 09:22'
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

実測 1（2026-10-06、TASK-674.1 を含むツリー。手元 10 コア、TSan、yes 40 本、BEFOLD_TEST_TIMEOUT_SECONDS=120。ログは .tmp/t673/、リポジトリには含まれない）: テストに一時的な診断ログ（待ちごとのラベル。コミットしない）を入れて回した。
- スイート単体 + 負荷 40 本: 0/40（1 回 16〜18 秒）。全体実行（--skip befoldCLITests）+ 負荷 40 本: 2/8 で同じ失敗を再現（run3 1114 秒、run7 1162 秒。どちらも「Time limit was exceeded: 600 seconds」）。単体では出ず、全体実行の混雑の中でだけ出る。
- 止まった待ちは 2 回とも最初の await、つまり waitForWebViewLoad の isReady（実 WKWebView の viewer.html ロード完了待ち）。その後の 2 回目の描画・ゲート・evaluateJavaScript には到達していない（isReady が解放されたあとで js1 / js2 の診断が出る順）。成功した 6 回でも isReady は 30 秒を超えて待っている。
- 結論（実測）: 『TASK-672 の上限なし化で、ゲートが開かれないまま待ち続けた』という仮説は否定。止まった時点では SlowFileReader のゲートはまだ作られていない。AC#2 の『修正前との比較』は、このテストが止まる場所がゲートの手前なので前提ごと外れる。
- 関連（コード・文書参照）: TASK-607 が同じ型（isReady が来ない）を扱い、真因は『Task.sleep 系ではメインランループが回らず実 WKWebView のロードが前進しない。並列実行では他のテストの Task.yield がたまたまランループを回すので、通るか来ないかの二極になる』だった。本テストの waitForWebViewLoad も同じ前提（yield スピンがランループを回す）に依存している。他のテストが終わった後（約 445 秒以降）も 650 秒以上来なかったので、単なる混雑ではなく『ロードが前進しない状態』の疑い。
- 未確認: なぜ前進しないか（WebContent プロセスの状態、didFinish が来ない/ナビゲーションの失敗、メインランループが回らない）。次は BEFOLD_RENDER_DIAGNOSTICS=1（TASK-607 の診断）と、650 秒止まった時点の sample / WebContent プロセス一覧で切り分ける。
<!-- SECTION:NOTES:END -->
