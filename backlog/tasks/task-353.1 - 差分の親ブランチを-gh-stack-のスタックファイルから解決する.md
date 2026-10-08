---
id: TASK-353.1
title: 差分の親ブランチを gh-stack のスタックファイルから解決する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-08 01:59'
updated_date: '2026-10-08 04:23'
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
- [x] #1 gh-stack のスタックに属するブランチでは、一つ前のブランチ（先頭なら trunk）を親として返す
- [x] #2 スタックファイルが無い・読めない・未知の schemaVersion・現在ブランチがどのスタックにも無い・detached HEAD の場合は、デフォルトブランチへ縮退し、縮退したことが解決結果から分かる
- [x] #3 親ブランチが refs/heads にも refs/remotes/origin にも無い場合もデフォルトブランチへ縮退する
- [x] #4 スタックファイルを common dir と worktree ごとの admin dir の両方から探す（gh-stack v0.1.1 は後者、新版は前者に置く）。実物で確認した結果を Notes に残す
- [x] #5 解決結果に基準ブランチ名と「親がデフォルトブランチと異なるか」が含まれ、メニューとラベルが main 上で再解決せずに読める
- [x] #6 上記の各ケースをユニットテストで担保し、既存の badgeAndDiffAgreeOnBranchChange を 3 基準に引数化する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-10-08）

### 置き場と形
- `GitComparisonTarget` enum（`.parentBranch` / `.defaultBranch` / `.head`）を `GitComparisonBase.swift`（111 行）に足し、`GitComparisonBaseResolving.comparisonBase(forRepositoryAt:)` を `comparisonBase(forRepositoryAt:target:)` に広げる。`.head` は libgit2 で "HEAD" を revparse するだけで特別扱いしない（バッジ側は HEAD..HEAD が空になるので「ブランチで変更」バッジが自然に消える = 353.3 AC#2 は無料で満たす）
- 解決結果は base の oid だけでなく **表示用の基準ブランチ名**と **親ブランチがデフォルトブランチと異なるか** を含む値型 `GitComparisonResolution` で返す。353.2 のラベル・メニューの出し分けはこの値を status スナップショットに載せて読む（メニューを開く瞬間に main で解決させない。チェック 5・6）
- 親ブランチの読み取りは新ファイル `GitParentBranchResolver.swift` に切る。JSON の解釈は `(Data, currentBranch) -> String?` の純粋関数にしてフィクスチャでテストする

### スタックファイルの場所（裏取り済み）
- gh-stack v0.1.1（手元で `gh extension list` 確認）は go-gh の `GitDir()` の結果に `gh-stack` を置く（cmd/utils.go v0.1.1 `loadStackOptional`）。gh-stack main は `git.CommonDir()` へ統合し、`internal/stack/migration.go` の `HasLegacyState` が「linked-worktree catalogs」を legacy として common dir へ移す。つまり **v0.1.1 は worktree ごとの admin dir（`.git/worktrees/<名前>/gh-stack`）、新版は common dir**
- 読み順: `git_repository_commondir` → `git_repository_path`（per-worktree）。両方試す。lock ファイル（`gh-stack.lock`）は無視
- 未確認: go-gh `GitDir()` が `rev-parse --git-dir` 相当であること（legacy 移行コードの記述から推定）。AC#4 の実測でスタックを 1 本作って `find "$(git rev-parse --git-common-dir)" -name gh-stack` で確かめる

### 縮退の判定（チェック 1）
- 「親が分からない」は事実で判定する: ファイル無し／JSON 不正／schemaVersion ≠ 1／現在ブランチが無い／detached HEAD／親 ref を revparse できない。いずれも `.defaultBranch` と同じ解決に落とし、`GitComparisonResolution` に「縮退した」ことを持たせる（ラベルが "main から" と出れば利用者に見える）
- 親 ref の解決は `refs/heads/<親>` → 無ければ `refs/remotes/origin/<親>`。ローカル削除済みでもリモートに残っていれば使う（AC#3 を「どちらにも無ければ縮退」に読み替える）
- `branches[i].base` フィールドは使わない（omitempty で空の可能性が未確認。隣接要素＋trunk で決める）。実物を見て base が常に入っているなら簡略化してよい

### テスト（チェック 7・9）
- 純粋関数: スタックに属する／先頭（trunk）／属さない／schemaVersion 2／壊れた JSON
- 統合: 実リポジトリに `gh-stack` を手書きして common dir と per-worktree dir の両方で解決できること、親ブランチ削除時の縮退
- 既存 `GitDiffComparisonBaseIntegrationTests.badgeAndDiffAgreeOnBranchChange` を target ごとに引数化し、3 基準でバッジと差分が一致することを守らせる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-10-08）

- 追加: GitComparisonTarget / GitComparisonResolution（GitComparisonBase.swift）、GitParentBranchResolver.swift（JSON 解釈は (Data, currentBranch) -> String? の純粋関数）。GitDiffReader / GitStatusReader は target: .defaultBranch を渡す（窓ごとの切替は 353.2）。
- 解決結果は baseID / baseBranch / parentDiffersFromDefault / degraded。parentDiffersFromDefault は target によらず同じ値。.head は baseBranch nil。
- テスト: swift test 全体 2018 件 + 72 件パス（known issue 1 件は既存）。純粋関数 5 件、実リポジトリ統合 7 件（common dir / per-worktree dir / 親削除 / origin 残存 / schemaVersion 2 / スタック外 / detached HEAD）、badgeAndDiffAgreeOnBranchChange を 3 基準に引数化（GitComparisonTargetAgreementTests へ移動。file_length 超過のため）。親の選択を trunk 固定に壊すと純粋関数・統合テストが落ちることを確認済み。

## AC#4 の実物確認（gh-stack v0.1.1、使い捨てリポジトリ、外部 push なし）

- 通常のチェックアウトで gh stack init --base main feat-a feat-b: <repo>/.git/gh-stack（JSON）と gh-stack.lock が生成。
- linked worktree（git worktree add）内で gh stack init: <common>/.git/worktrees/<名前>/gh-stack が生成され、common dir には書かれない。つまり v0.1.1 は per-worktree admin dir（Plan の推定どおり）。
- JSON は {schemaVersion:1, repository, stacks:[{trunk:{branch,head}, branches:[{branch, base}]}]}。実物では base が常に入っていたが、pullRequest は PR 作成前なので無かった。base は使わない方針のまま（隣接要素＋trunk で決まる）。
- 未確認: gh-stack 新版（common dir へ統合）の実物。上流ソースの記述（HasLegacyState）からの推定で、common dir も読む実装にしてある。
<!-- SECTION:NOTES:END -->
