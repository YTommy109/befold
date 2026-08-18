---
id: TASK-517
title: TSan ジョブで多数のテストが一斉に 240 秒の timeLimit に達して落ちる
status: To Do
assignee: []
created_date: '2026-08-18 11:25'
labels: []
dependencies:
  - TASK-516
priority: high
type: bug
ordinal: 757000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブで、無関係な 28 件のテストが**そろって** 240 秒の `.timeLimit` に達して落ちる。

## 事実（実測）

- run [32089661788](https://github.com/YTommy109/befold/actions/runs/32089661788)（main / commit 6ddfe5c4）の thread-sanitizer ジョブ。
  `Time limit was exceeded: 240.000 seconds` が 28 件。
  `✘ Test run with 1608 tests in 255 suites failed after 262.796 seconds with 30 issues.`
- **run 全体が 262 秒**で、28 件はいずれもちょうど 240.000 秒。個々が遅いのではなく、
  同時に走っていた分がまとめて停止した形。
- 240 秒は `Waiting.swift:23-31` が組み立てる `.timeLimit`（`BEFOLD_TEST_TIMEOUT_SECONDS`=120 の 2 倍）。
- 落ちたファイルは特定の機能に寄っていない: ViewerStoreFileGoneTests 6 / ViewerRendererContentUpdateIntegrationTests 5 /
  ViewerWindowControllerDiffPendingTests 4 / ViewerWindowControllerDiffTests 3 / ViewerRendererZoomIntegrationTests 3 /
  ViewerWindowManagerDiffTests 2 / ViewerStoreIntegrationTests 2 / ViewerRendererOneShotIntegrationTests 2 /
  GitStatusReaderIntegrationTests 2 / ViewerWindowControllerGitStatusTests 1。
  いずれも @MainActor で実際の非同期完了を待つテスト。
- このコミット 6ddfe5c4 は TASK-512（#558）そのもので、差分系テストの待ち合わせを
  `awaitSettled()` の await へ移した直後。つまり TASK-512 で直した形とは別の失敗。
- 他ジョブ（build-and-test / js-test / type-group-size）はすべて成功しており、TSan ジョブ限定。

## 見立て（未検証）

協調スレッドまたはメインアクターの枯渇で run 全体が前進しなくなった、という一斉停止の形。
[[task-516]] の「同期ブロックが協調スレッドを塞ぐ」が原因である可能性がある（同じ TSan ジョブで
別の回に現れており、塞がれた側の症状としてこの一斉タイムアウトが説明できる）。**両者が同一原因か
どうかは実測していない。** TASK-516 を直した後にこの現象が消えるかを確認するのが最短。

## 補足

同ジョブは直近 main で他にも落ちているが、次は既に別タスクで説明が付いている。
- run 32103739053（0b42f947）: ViewerNavigationCoordinator の unowned トラップ → [[task-515]] で修正済み
- run 31993974965（cdcd1175）: 差分系テストのサイドバー基準ディレクトリ待ち漏れ → [[task-512]] で修正済み（この run は修正前）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TASK-516 の修正後に TSan 全件実行を反復し、一斉タイムアウトが再発しないことを実測する
- [ ] #2 再発する場合は、停止時点で何が前進を止めているか（協調スレッド枯渇 / メインアクター輻輳 / 特定の待機）を実測で特定している
- [ ] #3 原因が並列度そのものなら、TSan ジョブの並列度または timeLimit の決め方をどう変えるかを判断し、理由を Notes に残している
<!-- AC:END -->
