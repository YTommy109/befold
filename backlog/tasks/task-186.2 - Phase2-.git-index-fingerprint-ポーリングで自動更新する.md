---
id: TASK-186.2
title: 'Phase2: 作業ツリー/index の変更に追従して自動更新する'
status: To Do
assignee: []
created_date: '2026-07-28 14:23'
updated_date: '2026-08-02 08:01'
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
FileWatcher 経由の変更通知を第一の契機として GitStatusSnapshot を無効化・再取得する。GitRepository.indexFingerprint(.git/index の mtime) は add/commit/checkout など index を動かす操作の検出とキャッシュ妥当性判定に用途を限定する（素の作業ツリー編集では mtime が変化しないため、ポーリング単独では編集に追従できない）。また git status は既定で index を refresh して mtime を書き換えうるため、status 実行には --no-optional-locks を付け、ポーリングとの自己励振ループを避ける。着手時に TASK-226（GitCommandRunner の async 化 / GitCommandFileIndex の actor 化）の要否を再評価する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 add/stage/commit 操作後、明示 refresh なしで数秒以内にバッジが更新される
- [ ] #2 表示中ファイルの編集保存が unstaged バッジに反映される
- [ ] #3 fingerprint 無変化時は不要な git 呼び出しが発生しない
- [ ] #4 作業ツリーでのファイル編集保存が、明示 refresh なしで unstaged バッジに反映される
- [ ] #5 add/stage/commit/checkout 操作後、明示 refresh なしで数秒以内にバッジが更新される
- [ ] #6 変更がない状態では不要な git 呼び出しが発生しない（status 実行自体が再取得を誘発しない）
- [ ] #7 TASK-226 の async 化を先行させるか否かを判断し、結論を Notes に記録する
<!-- AC:END -->
