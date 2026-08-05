---
id: TASK-302
title: performListing の git ステータス適用経路を一本化する
status: To Do
assignee: []
created_date: '2026-08-04 16:35'
labels:
  - git-filter
  - review-finding
  - refactor
dependencies:
  - TASK-299
  - TASK-300
priority: medium
type: task
ordinal: 475000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の PLAUSIBLE 指摘（design-debt）。performListing には git ステータス適用経路が 2 本ある（結合経路＝ガードを自前バンプで無効化して適用／分離経路＝通常の世代ガードで適用。SidebarNavigator.swift:221-237）。この関数の正しさが 3 つの順序機構（listingGeneration、gitStatusGeneration とそれを意図的に破る 225 行目のバンプ、FileListModel.pendingGitStatus の対付け）の相互作用に依存している。

この領域では TASK-291/293/294/296/297 と同型の順序回帰が 5 連続で起きており、「同型の回帰が続いたら設計の欠落を疑う」の条件を満たす。FileListModel.pendingGitStatus が既に提供している「一覧とステータスの原子的な対付け」を絞り込み点として、結合をそこに 1 回だけ持たせる形へ一般化できないか検討する（ADR + 段階移行を含む）。TASK-299/TASK-300 の修正で個別ガードがさらに増える場合、本タスクで吸収する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git ステータスの適用が単一の経路・単一のガード規約を通る（経路ごとの特例が残らない）
- [ ] #2 設計判断が ADR として記録されている
- [ ] #3 TASK-291/293/294/296/297 の回帰テストがすべて通る
<!-- AC:END -->
