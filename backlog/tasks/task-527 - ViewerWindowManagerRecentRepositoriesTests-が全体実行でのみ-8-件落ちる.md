---
id: TASK-527
title: ViewerWindowManagerRecentRepositoriesTests が全体実行でのみ 8 件落ちる
status: To Do
assignee: []
created_date: '2026-08-19 04:25'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 769000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

`swift test --skip Integration --skip FileWatcherTests` の全体実行で ViewerWindowManagerRecentRepositoriesTests の 8 件が落ちる。単体実行(`--filter ViewerWindowManagerRecentRepositoriesTests`)では 8 件とも pass する。

## 実測(2026-08-19、TASK-526 の作業中)

- 作業ツリー: 1548 tests / 14 issues、失敗はすべて ViewerWindowManagerRecentRepositoriesTests
- origin/main を `git archive` で別ディレクトリへ展開した pristine ツリー: 1540 tests / 14 issues、**同じ 8 件**が同じように落ちる → TASK-526 の変更とは無関係な既存の問題
- 単体実行: 8 tests pass(1.4 秒)。全体実行では各テストが 18〜25 秒かかっており、並列実行下でのみ壊れる

失敗の形は `fixture.store.entries()` が空・`controller.repositoryRoot` が nil で、リポジトリルート解決が着地しないまま判定している疑い。

## 着手条件

TASK-526 の作業では原因調査まで行っていない。実測ログは $CLAUDE_JOB_DIR に残っていないため、再現から取り直す必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 全体実行でも 8 件が安定して pass する
- [ ] #2 落ちていた原因(タイムアウト・共有状態・並列度のいずれか)を実測で特定し Notes に残す
<!-- AC:END -->
