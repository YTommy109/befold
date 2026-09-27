---
id: TASK-646
title: >-
  revealChangedFolders の「状態が同じなら何もしない」判定が SidebarGitStatus の全量比較で、組み直しの hot path
  で毎回走る
status: To Do
assignee: []
created_date: '2026-09-27 07:24'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befold/App/SidebarGitStatus.swift
priority: low
ordinal: 846000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-638（commit 5f7d3c2b）で `revealChangedFolders` に `guard previous?.status != status else { return }` を置き、コメントで「状態が同じなら候補を数えもしない」とした。`/code-review high` が、その判定自体のコストを指摘した。

## 現状（検証済み）

- `SidebarGitStatus` は `files: [String: GitFileStatus]` と `folders: [String: GitFolderStatus]` を持つ Equatable な struct。`!=` は 2 つの辞書の全量比較で、変更ファイル数に比例する。
- `revealChangedFolders` は `applyRows` の末尾で毎回呼ばれる。`applyRows` は一覧の着地・子リスト着地のまとめ組み直し（`scheduleRebuild`）・畳み・フォーカス復帰の取り直しのすべてで走る。TASK-637 が 12ms → まとめて 1 回へ最適化した経路の中で、毎回この比較が走る。
- 一方 `FileListModel.gitStatus` の `didSet` は既に `guard gitStatus != oldValue` で同値を弾いている。同じ比較を presenter 側で繰り返している。

## 方向

まず実測する（数千件の変更を持つリポジトリで `applyRows` 1 回あたりの比較コストがどれだけか）。無視できるなら Notes に実測を残して見送る。効くなら、`FileListModel` が `gitStatus` の変化ごとに進める世代（Int）を持ち、`lastReveal` はそれを記録して Int 比較にする（等価性の判定を didSet 1 箇所へ寄せる）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `applyRows` 1 回あたりの `SidebarGitStatus` 比較コストが、数千件規模の git 状態で実測され Notes に残っている
- [ ] #2 実測で無視できない場合、`revealChangedFolders` の同一判定が辞書の全量比較ではなく世代の比較になっている（無視できる場合は見送りの判断と根拠が Notes にある）
<!-- AC:END -->
