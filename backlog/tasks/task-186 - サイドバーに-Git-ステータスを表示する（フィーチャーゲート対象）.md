---
id: TASK-186
title: サイドバーに Git ステータスを表示する（フィーチャーゲート対象）
status: To Do
assignee: []
created_date: '2026-07-28 14:22'
updated_date: '2026-07-28 14:24'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: medium
ordinal: 261200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Git リポジトリ内のサイドバーファイル一覧で、変更ファイルに状態バッジ（1文字＋色）を表示する。staged(index)/unstaged(worktree)/untracked を区別し、さらに現在ブランチが base ブランチ（デフォルトブランチ自動検出＋merge-base）から変更したコミット済みファイルにもマークする。read-only 表示のみ。FeatureGate.inProgressFeaturesEnabled による露出制御下に置く。段階的に Phase 1〜3 のサブタスクで進める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Git リポジトリ内でサイドバー行の右端に状態バッジが表示される
- [ ] #2 staged / unstaged / untracked / branchModified を区別できる
- [ ] #3 staged+unstaged 両立時は index 側コードを優先表示しつつ色で worktree 変更も示す
- [ ] #4 非 Git・git 不在・status 取得失敗・変更なし ではバッジ非表示に縮退する
- [ ] #5 露出は FeatureGate.inProgressFeaturesEnabled で制御される
<!-- AC:END -->
