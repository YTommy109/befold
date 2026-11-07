---
id: TASK-907
title: CI の build-and-test (default) がテスト実行中に固まり、30 分のタイムアウトで打ち切られる
status: To Do
assignee: []
created_date: '2026-11-07T04:18:00Z'
labels:
  - test
  - bug
  - ci
  - test-infra
dependencies: []
references:
  - TASK-675
  - https://github.com/YTommy109/befold/actions/runs/42333763789
  - https://github.com/YTommy109/befold/pull/756
priority: medium
type: bug
ordinal: 873000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI が通常 6〜8 分のジョブで 30 分待たされ、失敗の情報も残らない。再実行すれば通るので、原因が分からないまま再実行で済ませる運用になりやすい。

観測（1 回のみ）: PR #756 の run 42333763789（attempt 1）、build-and-test (default)。Swift のテストは 03:28:34 に始まり、失敗 0 件のまま 03:29:34 を最後に出力が止まり、03:53 に timeout-minutes: 30 で打ち切られた。この時点で未完了は 20 スイート、最後の出力の直前には約 60 秒で終わったテストが続いていた（CI の BEFOLD_TEST_TIMEOUT_SECONDS は 60）。未完了には ViewerRendererRenderRaceTests、ViewerCanvasPixelTests、ViewerStoreFileGoneTests、ViewerWindowControllerDiffTests などがある。同じコミットの strict は成功し、再実行（attempt 2）は 6 分半で成功した。同じ変更を含む PR #757 も両方成功したので、PR #756 の変更が原因とは考えにくいが断定はできない。

未特定: どのテストが何を待って止まったか。今回のログにはプロセスの状態が無く、未完了のテストは並列実行のため大量に出る。TASK-675（TSan + CPU 負荷で実 WKWebView の didFinish が来ない）と同じ原因の可能性はあるが、未確認。あちらは負荷をかけた条件で、今回は通常の CI ジョブ。

手元での再現は flaky-test-investigator サブエージェントが使える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 固まった回に、どのテストが何を待っているかを後から確認できる情報が CI に残る
- [ ] #2 実際に固まった回の情報で原因が特定され、TASK-675 と同じか別かが Notes に記録されている
- [ ] #3 直せる原因なら直し、複数回の全体実行で再発しないことを実測している。直せないなら根拠と回避策が記録されている
<!-- AC:END -->
