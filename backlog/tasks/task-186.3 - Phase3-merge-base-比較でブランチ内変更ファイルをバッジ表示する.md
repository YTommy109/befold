---
id: TASK-186.3
title: 'Phase3: merge-base 比較でブランチ内変更ファイルをバッジ表示する'
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
ordinal: 261800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
デフォルトブランチを自動検出（git symbolic-ref --short refs/remotes/origin/HEAD、無ければローカル既定 main/master）し、git merge-base HEAD <default> と git diff --name-status -z <mergeBase> HEAD で、現在ブランチでコミット済み・作業ツリークリーンな変更ファイル（branchModified）を青系バッジで表示する。検出不可時は branchModified のみ無効化し他状態は継続表示する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 現在ブランチが base から変更したコミット済みファイルに branchModified バッジが表示される
- [ ] #2 worktree に変更のある staged/unstaged 状態が branchModified より優先/併記されて破綻しない
- [ ] #3 デフォルトブランチ検出不可時は branchModified のみ無効化され、staged/unstaged/untracked は表示される（ユニットテスト）
<!-- AC:END -->
