---
id: TASK-186.2
title: 'Phase2: .git/index fingerprint ポーリングで自動更新する'
status: To Do
assignee: []
created_date: '2026-07-28 14:23'
updated_date: '2026-07-28 14:24'
labels: []
dependencies:
  - TASK-186.1
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
parent_task_id: TASK-186
priority: medium
ordinal: 261600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitRepository.indexFingerprint(.git/index の mtime)の変化を数秒間隔でポーリングして GitStatusSnapshot を無効化・再取得する。表示中ファイル保存時（既存 FileWatcher 経由）の変更にも追従する。add/commit/checkout や作業ツリー編集がバッジに反映されるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 add/stage/commit 操作後、明示 refresh なしで数秒以内にバッジが更新される
- [ ] #2 表示中ファイルの編集保存が unstaged バッジに反映される
- [ ] #3 fingerprint 無変化時は不要な git 呼び出しが発生しない
<!-- AC:END -->
