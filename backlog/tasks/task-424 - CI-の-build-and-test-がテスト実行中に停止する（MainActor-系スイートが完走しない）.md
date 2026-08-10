---
id: TASK-424
title: CI の build-and-test がテスト実行中に停止する（@MainActor 系スイートが完走しない）
status: To Do
assignee: []
created_date: '2026-08-10 08:38'
labels:
  - ci
dependencies: []
priority: high
type: bug
ordinal: 504000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Actions の CI ワークフロー（.github/workflows/ci.yml）の build-and-test ジョブで、「テストを実行する」ステップ（swift test）が断続的に停止し、キャンセルされるまで数十分〜数時間 in_progress のまま進まなくなる。

実測（2026-08-10 時点）:
- 発生ラン: 2026-08-07 14:09（53 分でキャンセル）、2026-08-09 13:14（2 時間超でキャンセル）、2026-08-10 08:18（PR #460、25 分超で手動キャンセル）。いずれも build-and-test の swift test ステップ。
- 2026-08-09 のランのログでは、出力が 13:17:54 で完全に停止したあと一切進まない。未完了のまま残ったのは ViewerStore* / ViewerWindowController* / SidebarNavigator* / GitStatusReaderIntegrationTests など @MainActor 系のスイートが約 40 件。非 MainActor のスイート（パーサ系・CLI 系など）は完走している。
- 同じコミットをローカルで実行すると BEFOLD_TEST_TIMEOUT_SECONDS=60 で 1369 tests / 198 suites が 16 秒で全て通る。再実行すると CI も通ることがあり、再現性は低い。

疑い: どこかのテストが main actor をブロックしたまま待ちに入り、@MainActor のテストが総崩れで餓死している（BEFOLD_TEST_TIMEOUT_SECONDS の待機予算では抜けられない経路がある）。まず原因の切り分けが目的で、修正方針は調査後に決める。

副作用として、ハングしたランは macOS ランナーを最大 6 時間占有するため、切り分けと並行してジョブ側の時間上限も検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 停止時にどのテスト／どの待機がmain actor を保持しているかを、実測（ハング時のログ・スタック・再現手順のいずれか）で特定できている
- [ ] #2 特定できた待機が、待機予算を超えたら停止ではなく失敗として報告されるようになっている（無限に待つ経路が残っていない）
- [ ] #3 build-and-test ジョブに timeout-minutes が設定され、ハングしても数時間ランナーを占有しない
<!-- AC:END -->
