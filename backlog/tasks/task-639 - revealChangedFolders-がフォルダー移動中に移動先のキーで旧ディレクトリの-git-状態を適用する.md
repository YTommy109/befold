---
id: TASK-639
title: revealChangedFolders がフォルダー移動中に移動先のキーで旧ディレクトリの git 状態を適用する
status: To Do
assignee: []
created_date: '2026-09-27 06:23'
labels: []
dependencies:
  - TASK-638
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarListingCoordinator.swift
  - BefoldApp/befold/App/SidebarNavigator+FolderNavigation.swift
priority: low
type: bug
ordinal: 839000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637（commit c1de117a）のレビュー指摘。検証の結果、最終状態は復元されるが余分な展開が残りうることを確認した。

## 現象

`SidebarTreePresenter.revealChangedFolders` は適用先のキーを `fileListModel.currentDirectory` から作るが、行と git 状態の対は `entriesDirectory`（`applyRows` の `directory` 引数）に紐づいている。

レビュー表示中にディレクトリ A → B へ移動すると、`moveCurrentDirectory` が `currentDirectory = B` にして `discardExpansion` するが、A 向けに走っていた子リストの Task が着地すると `loadChildren` → `scheduleRebuild` → `rebuildRows` → `applyRows(lastListing(A), for: A)` の末尾で reveal が走り、キー B ≠ 印 A なので **A の git 状態**で B 配下の候補を全件展開し、`revealedDirectoryKey = B` にしてしまう。B の git 状態はこの時点では `FileListGitStatusGate` が `entriesDirectory`（まだ A）と照合して deferred のままなので、B の状態が先に見えることはない。`SidebarListingCoordinator` の `.toggleChangedFilesOnly` 経路にも同じ穴がある。

## 実害（検証済み）

B の一覧が着地すると `setEntries` → `promotePendingGitStatusIfNeeded` → `gitStatus` didSet → 差分 reveal が走るので、**B に必要なフォルダーはすべて開く**（レビューの「B の着地時に skip される」という記述は誤り。skip されるのは末尾の呼び出しだけ）。残るのは次の 2 点。

- A のスナップショットでは変更ありだが B の状態では clean なフォルダーが余分に開く（同一リポジトリ内の移動で、移動中に状態が変わった場合に限る）。
- B 着地前の子リスト着地で A の行が組み直される（一時的・無害）。

## 修正の方向

キーを `entriesDirectory`（`applyRows` の `directory` 引数）から作る、または `entriesDirectory != currentDirectory` の間は reveal を見送る。B の着地で全件 reveal が 1 回きれいに走る形にする。TASK-638 の後に行う（同じ関数の同じ行を触るため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 reveal の適用先キーは着地済みの一覧のディレクトリ（`entriesDirectory` / `applyRows` の `directory`）から作られ、`currentDirectory` だけが先に進んだ状態では reveal が走らない
- [ ] #2 移動中に旧ディレクトリの子リストが着地するケースをテストで再現し、移動先の展開集合が移動先の git 状態だけから求めた集合と一致する（旧状態由来の余分なキーが無い）
- [ ] #3 `.toggleChangedFilesOnly` 経路でも同じ判定が使われている（経路を分けない）
<!-- AC:END -->
