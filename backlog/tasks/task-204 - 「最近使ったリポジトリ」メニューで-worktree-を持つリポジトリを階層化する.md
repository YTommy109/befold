---
id: TASK-204
title: 「最近使ったリポジトリ」メニューで worktree を持つリポジトリを階層化する
status: To Do
assignee: []
created_date: '2026-07-31 02:02'
updated_date: '2026-07-31 07:00'
labels: []
dependencies:
  - TASK-190
priority: medium
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-190 で追加した「最近使ったリポジトリ」メニューは現状フラットな一覧になっている。worktree を持たないリポジトリはそのままの表示でよいが、worktree を持つリポジトリは項目数が増えて見通しが悪くなるため、リポジトリ配下に worktree をぶら下げる階層化（サブメニュー化）されたメニュー構成にしたい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 worktree を持たないリポジトリは従来どおりフラットな1項目として表示される
- [ ] #2 worktree を持つリポジトリは親項目化され、配下のサブメニューに各 worktree が表示される
- [ ] #3 サブメニューの各項目から該当 worktree を開ける
- [ ] #4 worktree の有無判定や一覧取得のロジックにテストがある
<!-- AC:END -->
