---
id: TASK-675
title: 全体実行 + CPU 負荷下で、実 WKWebView の viewer.html のロード完了（didFinish）が数分〜永久に来ない原因を特定する
status: To Do
assignee: []
created_date: 2026-10-07 00:58
updated_date: '2026-11-07T05:44:00Z'
labels:
  - test
  - bug
  - ci
  - test-infra
dependencies: []
references:
  - TASK-673
  - TASK-607
priority: low
type: bug
ordinal: 861000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-673 から切り出した原因探索。TSan + CPU 負荷 40 本（yes）の全体実行で、実 WKWebView の loadFileURL から didFinish までが数分かかる、または 1300 秒以上来ないことがある。再現率は修正後の有効な全体実行で 1/22 前後（TASK-673 の Notes に実測の全記録）。止まった回の sample では、テストプロセスのメインスレッドはランループを回しており、テストが起動した WebContent / Networking プロセスは mach_msg で完全にアイドル（両側とも何もしていない）。成功した回でも didFinish は他のテストが終わる実行の最後に届く。画面に出ていない WebView の WebContent が OS に低優先度として扱われている仮説と、UI-WebContent 間の通知が届かないまま両側がアイドルになる仮説があり、どちらも未検証。実機（CI の macOS ランナー）での観測はまだ無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 止まった回で、ロード完了が来ない理由（WebContent の起動・応答、ナビゲーションの要求の行方、通知の欠落のどれか）が実測で特定されている
- [ ] #2 原因が特定でき、直せるものなら直した上で、同じ負荷・複数回の全体実行で再発しないことを実測している。直せない（WebKit / OS 側）なら、その根拠が記録されている
- [ ] #3 実験の運用（ビルド・テストの並走をしない、止め忘れを確認する）が守られた有効な標本だけで判断している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07: 通常の CI ジョブ（TSan・追加負荷なし）で、同じ原因かもしれないハングを 1 回観測した。実 WKWebView を使うスイートも未完了に含まれる。sample が無いので同一とは確認できていない。詳細は TASK-907。

2026-11-07: 原因の有力な候補を TASK-907 で特定した。PDFView の Vision 解析が libdispatch のワーカー上限 64 本を使い切り、実 WKWebView のロードが止まる（ワーカーを塞ぐ実験で再現。成功した回でも didFinish が実行の最後に届く観測とも整合）。TSan ジョブも PDF を別プロセスに分けた。TSan + 負荷 40 本での再発なしは未測定なので、本タスクの完了条件 2 は未達。
<!-- SECTION:NOTES:END -->
