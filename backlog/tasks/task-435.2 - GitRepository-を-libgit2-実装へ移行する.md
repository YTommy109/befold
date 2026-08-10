---
id: TASK-435.2
title: GitRepository を libgit2 実装へ移行する
status: To Do
assignee: []
created_date: '2026-08-10 15:02'
labels:
  - refactor
dependencies:
  - TASK-435.1
parent_task_id: TASK-435
priority: high
type: task
ordinal: 667000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。`GitRepository`（`BefoldApp/befold/App/GitRepository.swift`）の 4 呼び出しを libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| リポジトリルート解決 | `rev-parse --show-toplevel` | GitRepository.swift:82 | `git_repository_open_ext` + `git_repository_workdir` |
| 追跡ファイル一覧 | `ls-files -z` | GitRepository.swift:97 | `git_repository_index` + `git_index_get_byindex` の走査 |
| worktree 判定 | `rev-parse --git-common-dir --git-dir` | GitRepository.swift:125 | `git_repository_path` / `git_repository_commondir` / `git_repository_is_worktree` |
| worktree 列挙 | `worktree list --porcelain` | GitRepository.swift:144 | `git_worktree_list` + `git_worktree_lookup` + `git_worktree_path` |

## 実測で判明している差分（親タスク Notes 参照）

1. `git_worktree_list` は**リンク worktree だけ**を返し、メイン worktree を含まない。現行の `git worktree list --porcelain` はメインも含むため、メイン側は `git_repository_commondir` から自前で補う。
2. `git_worktree_*` はブランチ名を返さない。`GitWorktree` がブランチ名を持つため、各 worktree を開いて HEAD を読む手当てが要る。
3. index 走査は submodule の gitlink（例 `vendor/sub`）も含む。`git ls-files` と同じ挙動。

## 既存の縮退規約を保つこと

`GitRootLookup` の `.root` / `.notARepository`（確定・キャッシュ可）/ `.undetermined`（不明・キャッシュ不可）の 3 値の意味を変えない。libgit2 では「リポジトリでないことが確定した」と「開けなかった（未知の extensions・権限不足）」の区別が必要で、後者は `.undetermined` 側へ落とす。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitRepository の 4 呼び出しがすべて libgit2 実装に置き換わり、このファイルから GitCommandRunning への依存が消えている
- [ ] #2 GitRepositoryIntegrationTests / GitRepositoryTests の既存テストが同等の期待値で通る
- [ ] #3 worktree 列挙がメイン worktree を含み、各エントリのブランチ名が従来と同じ結果を返すことがテストで担保されている
- [ ] #4 リポジトリでないことが確定した場合と開けなかった場合が区別され、それぞれ .notARepository / .undetermined へ写像されることがテストで担保されている
<!-- AC:END -->
