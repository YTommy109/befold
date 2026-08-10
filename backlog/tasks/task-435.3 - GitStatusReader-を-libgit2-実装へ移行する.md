---
id: TASK-435.3
title: GitStatusReader を libgit2 実装へ移行する
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
ordinal: 668000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。`GitStatusReader`（`BefoldApp/befold/App/GitStatusReader.swift`, 341 行）の 3 呼び出しと、その出力パーサを libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| 作業ツリー状態 | `--no-optional-locks status --porcelain=v2 -z` | GitStatusReader.swift:88 | `git_status_list_new` + `git_status_byindex` |
| submodule パス | `config -z --file .gitmodules --get-regexp` | GitStatusReader.swift:160 | `git_submodule_foreach` |
| ブランチ差分ファイル | `diff --name-status -z <base> HEAD` | GitStatusReader.swift:189 | `git_diff_tree_to_tree` + `git_diff_get_delta` |

撤去対象のパーサ: `parsePorcelainV2` / `fieldsBeforePath` / `submodulePath(in:)` / `parseRecord` / `parseUntrackedEntry` / `parseChangedEntry` / `parseConfigValues` / `parseNameStatus`。

## 実測で確認済みの対応関係（親タスク Notes 参照）

porcelain=v2 の XY 2 文字は `git_status_entry.head_to_index.status`（X）と `.index_to_workdir.status`（Y）を `git_delta_t` → 文字へ写像すれば再現できる。フィクスチャ 6 パターン（staged 追加 / workdir 削除 / rename / staged 変更 / workdir 変更 / untracked）でエントリ数・パス・rename の元パスまで一致することを実測済み。

必要なオプション: `GIT_STATUS_OPT_INCLUDE_UNTRACKED` / `RENAMES_HEAD_TO_INDEX` / `RENAMES_INDEX_TO_WORKDIR` / `EXCLUDE_SUBMODULES`。

## 注意

`GitFileStatus.Change` は porcelain の XY コード（Character）をそのまま持つ。ここを内部の列挙型へ変えるかは設計判断であり、`/review-design` で扱うこと。表示側（SidebarGitStatus / GitStatusBadge / GitFolderStatus）とそのテストは XY 由来の値に依存している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitStatusReader の 3 呼び出しがすべて libgit2 実装に置き換わり、このファイルから GitCommandRunning への依存が消えている
- [ ] #2 porcelain=v2 のテキストパーサ（parsePorcelainV2 ほか）が撤去され、GitStatusReaderTests / GitStatusReaderIntegrationTests の既存テストが同等の期待値で通る（AC #4）
- [ ] #3 submodule の境界検出が git_submodule_foreach ベースで再実装され、従来と同じ結果を返すことがテストで担保されている（AC #5 の一部）
- [ ] #4 ブランチ差分ファイルの取得が従来と同じ結果（rename/copy の元パス扱いを含む）を返すことがテストで担保されている
<!-- AC:END -->
