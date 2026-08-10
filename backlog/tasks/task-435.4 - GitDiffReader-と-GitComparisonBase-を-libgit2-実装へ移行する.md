---
id: TASK-435.4
title: GitDiffReader と GitComparisonBase を libgit2 実装へ移行する
status: To Do
assignee: []
created_date: '2026-08-10 15:03'
labels:
  - refactor
dependencies:
  - TASK-435.1
parent_task_id: TASK-435
priority: high
type: task
ordinal: 669000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。差分本体の生成と比較起点の解決を libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| 差分本体 | `diff --no-color --no-ext-diff -U1000000 <base> -- <path>` | GitDiffReader.swift:55 | `git_diff_tree_to_workdir_with_index`（`context_lines = 1_000_000`, pathspec 1 件）+ `git_diff_to_buf(GIT_DIFF_FORMAT_PATCH)` |
| 管理外/コミット無しの切り分け | `rev-parse --git-dir` | GitDiffReader.swift:73 | リポジトリを開けたか + `git_repository_head_unborn` |
| 未追跡判定 | `ls-files --error-unmatch -z -- <path>` | GitDiffReader.swift:91 | `git_index_get_bypath` |
| 比較起点 | `merge-base HEAD <default>` | GitComparisonBase.swift:37 | `git_merge_base` |
| 既定ブランチ探索 | `rev-parse --verify --quiet main` / `master` | GitComparisonBase.swift:53 | `git_branch_lookup(GIT_BRANCH_LOCAL)` |
| origin の既定ブランチ | `symbolic-ref --short refs/remotes/origin/HEAD` | GitComparisonBase.swift:62 | `git_reference_lookup` + `git_reference_symbolic_target` |

## 実測で確認済み（親タスク Notes 参照）

`context_lines = 1_000_000` + `git_diff_to_buf` の出力が `git diff --no-color --no-ext-diff -U1000000` と**バイト単位で一致**した。したがって viewer.js の `parseUnifiedDiff` は無改修で足りる見込み。

## 注意

`GitDiffReader.isBinaryDiff` は git の固定文言（`Binary files ` / `GIT binary patch`）を行頭一致で見ている。libgit2 側では `git_diff_delta.flags` の `GIT_DIFF_FLAG_BINARY` で判定できるため、文字列一致をやめる余地がある（`/review-design` で扱う）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitDiffReader / GitComparisonBaseResolver の 6 呼び出しがすべて libgit2 実装に置き換わり、両ファイルから GitCommandRunning への依存が消えている
- [ ] #2 -U1000000 相当の全文コンテキスト diff が再現され、viewer.js の parseUnifiedDiff が無改修で従来どおり描画できる（AC #3）
- [ ] #3 GitDiffReaderIntegrationTests の既存テストが同等の期待値で通る（バイナリ判定・未追跡・コミット無し・管理外の切り分けを含む）
- [ ] #4 比較起点の解決（merge-base / 既定ブランチ探索 / origin の既定ブランチ）が従来と同じ結果を返すことがテストで担保されている（AC #5 の一部）
<!-- AC:END -->
