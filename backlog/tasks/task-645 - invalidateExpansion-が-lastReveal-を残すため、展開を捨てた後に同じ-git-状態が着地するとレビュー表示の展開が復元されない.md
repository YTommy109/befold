---
id: TASK-645
title: invalidateExpansion が lastReveal を残すため、展開を捨てた後に同じ git 状態が着地するとレビュー表示の展開が復元されない
status: To Do
assignee: []
created_date: '2026-09-27 07:24'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: medium
ordinal: 845000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-638（commit 5f7d3c2b）で `revealChangedFolders` の `since:` 引数をやめ、presenter が最後に適用した状態 `lastReveal`（directoryKey・status・targets）を持つ形にした。`/code-review high` が `invalidateExpansion` との組み合わせの穴を指摘し、コードで裏を取った。

## 現状（検証済み）

- `SidebarTreePresenter.invalidateExpansion()` は `expansion.invalidateAll()` と `childTasks.removeAll()` だけで、`lastReveal` は残す。
- `revealChangedFolders` は `lastReveal.directoryKey == directoryKey && lastReveal.status == status` なら「適用済み」として早期 return する。
- したがってレビュー表示中に `navigateToFolder(現在のディレクトリ)` 等で `discardExpansion` → `invalidateExpansion` が走ると `expandedKeys` は空になるのに、続く一覧の着地（`applyRows` → `revealChangedFolders`）は同じ directoryKey・同じ status を見て何も開かない。git 状態が実際に変わるまで、レビュー表示の展開は黙って消えたままになる。
- `lastReveal` の「前回の候補」は、それが作った展開が存在している間だけ意味を持つ。展開を捨てる reset と同じ場所で捨てるべき値。

## 方向

`invalidateExpansion()` で `lastReveal = nil` にする（単純化: `lastReveal` の寿命を `expansion` に揃える）。`Reveal` の doc にその寿命を書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 レビュー表示で展開が入った後に `invalidateExpansion()`（`navigateToFolder` 経由でよい）を挟み、同じ git 状態で一覧が着地したとき、変更フォルダーが再び展開されるテストがある
- [ ] #2 `lastReveal`（`Reveal`）の doc コメントに、値の寿命が `expansion` と同じであることが書かれている
<!-- AC:END -->
