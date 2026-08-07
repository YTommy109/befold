---
id: TASK-350
title: TSan で GitRepositoryIntegrationTests の worktree 一覧テストが 1 回失敗した
status: To Do
assignee: []
created_date: '2026-08-07 02:39'
labels:
  - test
  - flaky
dependencies: []
priority: low
type: bug
ordinal: 610000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
main の CI（run 31141164942）の thread-sanitizer ジョブで `GitRepositoryIntegrationTests`「git を実行できない場合の worktree 一覧は空になる」（GitRepositoryIntegrationTests.swift:164）が失敗した。

`repo.worktrees(forRoot:)` が空を期待するところで、`[GitWorktree(root: ..., isMain: true, branch: "master")]` を返している。つまり「git を実行できない」状況を作れておらず、実際に git が動いてしまっている。

再現できていない: ローカルで TSan 付きの当該スイート実行を 3 回試みたがいずれも 9 件通過（0.2〜0.4 秒）。CI の過去 12 回の main CI にこのテストの失敗は無い。

差分まわり（TASK-346〜348）とは無関係のコード領域。PATH を差し替えて git を見つからなくする類の仕掛けが、TSan の遅延や並列実行下で他テストと干渉している可能性がある（未確認）。

次に再現したら、その時点の実行ログを保存して着手する。1 例のみでは仕掛けの特定ができない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「git を実行できない」状況の作り方が、他テストと並行しても壊れないことが確認されている
- [ ] #2 同種の失敗が TSan の全体実行 10 回で再発しない
<!-- AC:END -->
