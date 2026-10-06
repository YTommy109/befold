---
id: TASK-673
title: >-
  ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS
  が thread-sanitizer + 高負荷で 600 秒の time limit まで終わらないことがある
status: To Do
assignee: []
created_date: '2026-10-06 06:00'
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
- [ ] #1 このテストが止まる await（waitForWebViewLoad の 3 つの待ち・evaluateJavaScript のどれか）が特定されている
- [ ] #2 修正前（TASK-672 の修正を含まないツリー）と修正後で、同じ負荷・同じ回数の発生率が比較され、修正由来かどうかが判定されている
- [ ] #3 修正由来なら TASK-672 の修正の見直し、既存の flaky ならその原因への対処が入り、同じ負荷で複数回まわして再発しないことを実測している
<!-- AC:END -->
