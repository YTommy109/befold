---
id: TASK-228
title: 「最近使ったリポジトリ」メニュー表示時の pruneMissing とアイコン取得をメニュー外へ逃がす
status: To Do
assignee: []
created_date: '2026-07-31 09:15'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 350000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentRepositoriesMenuController.menuNeedsUpdate (befold/App/RecentRepositoriesMenuController.swift:25-41) がメニューを開いた瞬間の MainActor 上で pruneMissing()（最大 10 件の isDirectory stat）と NSWorkspace.icon(forFile:) を件数ぶん実行する。アンマウント済み/応答しないネットワークマウント上の worktree が履歴に残っていると File メニューを開いた瞬間に固まる。prune は起動時/定期の Task.detached へ移し、表示は保存済みリストをそのまま出す（存在しないものは開いた時点で既存の FileNotFound 経路に委ねる）。RecentDocumentsMenuController.swift:33 の icon 取得も同種。TASK-204（worktree 階層化）と同じファイルを触るため実施順に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 メニューを開いた瞬間に stat・アイコン取得による MainActor ブロックが発生しない
- [ ] #2 存在しないエントリの整理が別タイミングで行われ、開こうとした場合は既存のエラー経路で通知される
<!-- AC:END -->
