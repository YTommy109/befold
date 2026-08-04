---
id: TASK-303
title: 絞り込み OFF へのトグルで全ウィンドウが不要な git status を実行する
status: To Do
assignee: []
created_date: '2026-08-04 16:36'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: low
type: bug
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の CONFIRMED 指摘。ViewerWindowManager.toggleChangedFilesOnly（ViewerWindowManager.swift:114-116）はトグル方向に関係なく全ウィンドウで applyChangedFilesOnlyToggle → refreshGitStatuses を実行する。OFF へのトグルでは絞り込みに新しい git 状態は不要で、大きいリポジトリを複数ウィンドウで開いていると、トグルのたびにウィンドウ数分の git status サブプロセスが同時起動する。TASK-297 がナビゲーション経路で削ったのと同種の不要な git 実行。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OFF へのトグルで git status サブプロセスが起動しない（バッジは既存状態を維持）
- [ ] #2 ON へのトグルでは従来どおり最新の git 状態で絞り込まれる
<!-- AC:END -->
