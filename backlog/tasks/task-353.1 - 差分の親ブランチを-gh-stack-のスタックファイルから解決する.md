---
id: TASK-353.1
title: 差分の親ブランチを gh-stack のスタックファイルから解決する
status: To Do
assignee: []
created_date: '2026-10-08 01:59'
updated_date: '2026-10-08 02:07'
labels: []
milestone: m-11
dependencies: []
parent_task_id: TASK-353
priority: medium
ordinal: 862000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-353 の「このブランチの変更」は `merge-base(HEAD, 親ブランチ)` を基準にする。git はブランチの親を記録しないため、親ブランチは stacked PR ツールの記録から得る。

## 2026-10-08 の調査

- git config には親の情報が無い（`git config --get-regexp "branch\..*"` は upstream が自分自身か main を指すだけ）
- gh-stack v0.1.1 は `<gitDir>/gh-stack` に JSON を置く（github/gh-stack `internal/stack/stack.go` の `stackFileName` / `stackFilePath`）。`{schemaVersion: 1, repository, stacks: [{trunk: {branch, head}, branches: [{branch, head, base, pullRequest}]}]}` の形で、`branches` は下から上の順。親は 1 つ前の要素、先頭なら `trunk`
- 調査時点ではこのリポジトリにスタックファイルが無く（マージ済みで消えたと見られる）、**実物は未確認**
- **未確認**: gh-stack の `gitDir` が worktree ごとの `.git/worktrees/<名前>` か共有の `.git` か（go-gh の `client.GitDir` 次第）。スタックを作った状態で `find "$(git rev-parse --git-common-dir)" -name gh-stack` を実行して確かめる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gh-stack のスタックに属するブランチでは、一つ前のブランチ（先頭なら trunk）を親として返す
- [ ] #2 スタックファイルが無い・読めない・未知の schemaVersion・現在ブランチがどのスタックにも無い場合は、デフォルトブランチへ縮退する
- [ ] #3 親ブランチがローカルに存在しない場合（削除済み・マージ済み）もデフォルトブランチへ縮退する
- [ ] #4 worktree で作業しているときもスタックファイルが見つかる（保存場所を実物で確認した結果を Notes に残す）
- [ ] #5 上記の各ケースをユニットテストで担保する
<!-- AC:END -->
