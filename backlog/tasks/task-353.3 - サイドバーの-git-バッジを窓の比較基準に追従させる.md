---
id: TASK-353.3
title: サイドバーの git バッジを窓の比較基準に追従させる
status: To Do
assignee: []
created_date: '2026-10-08 02:00'
labels: []
dependencies:
  - TASK-353.2
parent_task_id: TASK-353
priority: medium
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-352 で、差分ビューアとサイドバーのバッジの基準を `GitComparisonBase` に統一した（バッジは変更ありなのに差分が空、という食い違いを解消した）。TASK-353.2 で差分の基準を窓ごとに切り替えられるようにすると、バッジが固定のままでは同じ食い違いが別の形で戻る。

現状のバッジは 2 系統（`GitStatusReader.status(forRepositoryAt:)`）: 作業ツリーの staged / unstaged / untracked と、`branchChanges(in:base:)` による base..HEAD の「ブランチで変更」。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「このブランチの変更」「スタック全体の変更」では、ブランチで変更のバッジがその基準..HEAD の範囲に付く
- [ ] #2 「作業中の変更」では、ブランチで変更のバッジを出さない
- [ ] #3 「変更のみ表示」の絞り込みも同じ基準に従う
- [ ] #4 基準を切り替えたときにバッジが再計算される
<!-- AC:END -->
