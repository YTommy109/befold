---
id: TASK-517
title: TSan ジョブで多数のテストが一斉に 240 秒の timeLimit に達して落ちる
status: Done
assignee: []
created_date: '2026-08-18 11:25'
updated_date: '2026-08-19 01:32'
labels: []
dependencies: []
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
- [x] #1 一斉タイムアウトの原因が「.timeLimit が run 全体の壁時計を測ること」であると実測で特定されている
- [x] #2 .timeLimit の決め方がポーリング予算（BEFOLD_TEST_TIMEOUT_SECONDS）から切り離されている
- [x] #3 予算から導く実装へ戻すと落ちるテストがある
- [x] #4 CI（build-and-test / thread-sanitizer）が緑になる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因（実測で確定）

起票時の見立て（協調スレッド枯渇 / TASK-516 が原因）は**否定された**。真因は
`.timeLimit` の決め方そのもの。

`.timeLimit` が測るのは「そのテストの作業時間」ではなく**テスト開始からの壁時計**で、
全テストがほぼ同時に開始され `@MainActor` で直列化される full suite では、実質
「run 全体の長さ」を測る。それをポーリング予算の 2 倍から導いていたため、
**コードが正しくてもテストが増えて run が伸びるだけで慢性的に赤になる**構造だった。

| | run 全体 | 打ち切り | 結果 |
|---|---|---|---|
| ローカル（05ec6b84・1645 件） | 36.0 秒 | 120 秒 | 緑 |
| CI build-and-test | 136 秒 | 120 秒（予算 60 の 2 倍） | 赤 34 件 |
| CI thread-sanitizer | 265 秒 | 240 秒（予算 120 の 2 倍） | 赤 約 50 件 |

決定的な証拠:

- TSan 限定ではない。run 32160440586 では TSan 無しの build-and-test でも同じ形で落ちた
- 純粋な enum のテスト（`material の expanded / loading / failed は互いに素`）が
  `passed after 218.168 seconds` と報告
- 50ms sleep して cancel するだけの `WaitingTests.swift:54` が 260.9 秒で打ち切られた
- ローカル全件実行では、個々のテストが報告する最大所要時間 35.97 秒が run 全体 36.0 秒と一致

## 対処

`testTimeLimit()` を予算から導くのをやめ、run 全体の壁時計スケールの定数にした
（既定 10 分 / `BEFOLD_TEST_TIME_LIMIT_MINUTES` で上書き可）。予算
`BEFOLD_TEST_TIMEOUT_SECONDS` は待機ヘルパー専用に戻した。並列度は変えていない。
本来のハング検知はこの 10 分とジョブ側の `timeout-minutes`（30 / 60）で二重に担保される。

破れたら落ちるもの: `TestTimeLimitTests`（befoldTests/WaitingTests.swift）。予算から
導く実装へ戻すと 4 テストとも落ちることを、実際に戻して実測で確認した。

## TASK-516 との関係

本件は TASK-516 と独立。TASK-516（同期ブロックが協調スレッドを塞ぐ）は本件の原因では
なかったため、dependencies の前提は成立していない。TASK-516 自体は別途扱う。

## 完了確認（マージ後の main / run 32204876972）

全ジョブ緑。**thread-sanitizer も含む。**

- build-and-test: `✔ Test run with 1649 tests in 264 suites passed after 73.767 seconds.`
- thread-sanitizer: `✔ Test run with 1649 tests in 264 suites passed after 142.689 seconds.`

打ち切り 600 秒に対し TSan の run 全体は 142.7 秒で、4 倍以上の余裕がある。旧実装
（打ち切り 240 秒）では直前の run が 265 秒で落ちていた位置。

`docs/dev/native-app-design.md` は更新していない。本件はテスト基盤（打ち切りの決め方）
だけの変更で、アプリの仕様・構成に現れないため。根拠は `Waiting.swift` の doc コメントと
`.swiftlint.yml` の `hardcoded_time_limit` ルールのコメントに置いた。

タイトルは起票時のまま「TSan ジョブで…」だが、実測では TSan 限定ではなかった
（TSan 無しの build-and-test でも同じ形で落ちた）。
<!-- SECTION:NOTES:END -->
