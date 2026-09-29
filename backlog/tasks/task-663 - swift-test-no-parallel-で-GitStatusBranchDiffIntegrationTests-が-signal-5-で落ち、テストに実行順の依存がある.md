---
id: TASK-663
title: >-
  swift test --no-parallel で GitStatusBranchDiffIntegrationTests が signal 5
  で落ち、テストに実行順の依存がある
status: To Do
assignee: []
created_date: '2026-09-29 04:30'
labels: []
dependencies: []
priority: medium
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-29 の速度計測（TASK-662）で見つかった。

- `swift test --no-parallel` を回すと、`GitStatusBranchDiffIntegrationTests` の最初のテスト「base ブランチからのコミット済み変更に branchModified が付く」の開始直後に、テストプロセスが `exited with unexpected signal code 5`（trap）で落ちる。直前に走っていたのは `GitStatusBadgeTests`
- 同じスイートを単独で回すと、直列でも並列でも 4 件とも緑（`--filter GitStatusBranchDiffIntegrationTests`、`--no-parallel` 付きでも 0.5 秒で pass）
- 通常の並列実行では落ちていない

つまり、先に走った何か（直列順で前にある全スイートのどれか）が残した状態に依存して trap している。並列実行では順序が変わるため隠れているだけで、TASK-662 の並列化・MainActor 解除の作業で順序が変わると表面化しうる。1 回の再現なので flaky かどうかは未確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 --no-parallel の全体実行で再現するかを複数回測り、再現条件（先行するスイート）を特定している
- [ ] #2 trap の原因が直っている（検知を緩める・スイートを skip する形ではなく）
- [ ] #3 --no-parallel の全体実行が緑になる
<!-- AC:END -->
