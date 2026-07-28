---
id: TASK-186.1
title: 'Phase1: porcelain status で staged/unstaged/untracked をバッジ表示する'
status: To Do
assignee: []
created_date: '2026-07-28 14:22'
updated_date: '2026-07-28 14:24'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
parent_task_id: TASK-186
priority: medium
ordinal: 261400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitStatusReader（git status --porcelain=v2 -z）と GitStatusStore（@MainActor @Observable, ルート単位キャッシュ）を新設し、FileListModel/FileListEntryRow に url→GitFileStatus のバッジ描画を追加する。更新契機は refresh + ウィンドウキー化時。GitCommandRunner の hardeningOptions を通し、非リポジトリ/git不在/reject は status 無しに縮退する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 一時 Git リポジトリで staged/unstaged/untracked が正しく判別される（porcelain v2 パースのユニットテスト）
- [ ] #2 GitFileStatus→バッジ文字/色の写像が純粋関数としてテストされ、staged+unstaged 両立時は index 優先になる
- [ ] #3 サイドバー行右端にバッジが描画され、ディレクトリ移動・フォーカス復帰で更新される
- [ ] #4 非 Git / git 不在 / コマンド reject でバッジ非表示に縮退する
<!-- AC:END -->
