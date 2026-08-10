---
id: TASK-437
title: refreshesDiffWhenGitStatusApplied が CI で待機上限に達して落ちるのを直す
status: To Do
assignee: []
created_date: '2026-08-10 14:42'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 103500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowControllerDiffTests の「git 状態が反映されたら差分も取り直す」（refreshesDiffWhenGitStatusApplied、ViewerWindowControllerDiffTests.swift:164）が CI で待機上限に達して落ちる。gitStatusDidApply() 後の差分取得は detached の utility タスクを経由するため、全スイート並列実行では協調スレッドの空き待ちになる。テスト側は既に既定 10 秒では足りず timeout: testTimeout(fallback: 60) まで伸ばしてあるが、それでも足りていない。

実測（2 例、いずれも別コミット・別ジョブ）:
- main: run 31388117702 / thread-sanitizer ジョブ（BEFOLD_TEST_TIMEOUT_SECONDS=120）。『waitUntilOnMainActor が 120.0 seconds 以内に条件を満たさなかった』でこの 1 件だけ失敗し、1389 tests / 202 suites の run が exit 1。
- PR #472: run 31398484119 / build-and-test ジョブ（同 60）。同じ箇所・同じメッセージで 60 秒に達して失敗。

予算を伸ばす方向はすでに 2 段（10→60→120）踏んでおり、120 秒でも落ちているため上限引き上げでは解決しない。取得経路（detached utility タスク）をテストから待てる形にする、優先度を上げる、あるいはテスト側で取得完了を観測可能な同期点に変える、といった構造側の対処を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI の build-and-test と thread-sanitizer の双方で refreshesDiffWhenGitStatusApplied が待機上限に達しないこと（連続 3 回の CI 実行で確認する）
- [ ] #2 対処が『待機予算を伸ばす』だけになっていないこと。取得経路またはテストの同期点を変えた理由を Implementation Notes に残す
- [ ] #3 同じ経路に依存する他のテスト（ViewerWindowControllerDiffTests の他ケース）も同じ形で待っているなら併せて直す
<!-- AC:END -->
