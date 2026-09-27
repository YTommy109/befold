---
id: TASK-645
title: invalidateExpansion が lastReveal を残すため、展開を捨てた後に同じ git 状態が着地するとレビュー表示の展開が復元されない
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 07:24'
updated_date: '2026-09-27 08:04'
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
- [x] #1 レビュー表示で展開が入った後に `invalidateExpansion()`（`navigateToFolder` 経由でよい）を挟み、同じ git 状態で一覧が着地したとき、変更フォルダーが再び展開されるテストがある
- [x] #2 `lastReveal`（`Reveal`）の doc コメントに、値の寿命が `expansion` と同じであることが書かれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. invalidateExpansion() で lastReveal = nil にし、寿命を expansion に揃える 2. Reveal の doc に寿命を書く 3. navigateToFolder(同じディレクトリ) を挟んだ再展開テストを足す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 起票どおり invalidateExpansion() で lastReveal を捨てる。単純化の検討: 状態・分岐は増やさず、既存の reset 1 箇所に寿命を揃えるだけで済むためこれ以上の単純化は無い。
破れたら落ちるもの: SidebarNavigatorReviewExpansionTests.discardedExpansionIsRevealedAgainWithSameStatus。修正前は SidebarNavigatorReviewExpansionTests.swift:186 の expandedFolderKeys == [a] で失敗（実測）、修正後は通過。
検証: swift test --skip Integration --skip FileWatcherTests で 1891 件 + 66 件すべて通過。swiftlint は origin/main と diff ゼロ（両側 46 件、真の新規なし・解消なし）。
docs: viewer-ui.md の「レビュー表示」節は既に『レビュー表示中のフォルダー移動』を契機として約束しており、今回の修正は実装を仕様へ合わせるもの。更新は不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
invalidateExpansion() が lastReveal を残していたため、展開を捨てた後に同じ git 状態で一覧が着地しても『適用済み』と判定され、レビュー表示の展開が開き直らなかった。lastReveal の寿命を expansion に揃え（invalidateExpansion で nil にする）、Reveal の doc に寿命を明記した。同じディレクトリへの navigateToFolder を挟むと変更フォルダーが再び開くことを見る回帰テストを追加（修正前に失敗することを実測）。
<!-- SECTION:FINAL_SUMMARY:END -->
