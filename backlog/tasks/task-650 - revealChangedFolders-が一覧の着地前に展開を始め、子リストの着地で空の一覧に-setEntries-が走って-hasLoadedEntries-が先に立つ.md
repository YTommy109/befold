---
id: TASK-650
title: >-
  revealChangedFolders が一覧の着地前に展開を始め、子リストの着地で空の一覧に setEntries が走って
  hasLoadedEntries が先に立つ
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 08:49'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: medium
ordinal: 850000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。コードで裏を取った。

## 現状（検証済み）

- `FileListModel.init` は `entriesDirectory = currentDirectory` で始まる。したがって窓を開いた直後、ルートの一覧が着地する前でも `revealChangedFolders` の `directoryKey == currentDirectory.normalizedPathKey` ガードは通る。
- `revealChangedFolders` に `hasLoadedEntries` のガードは無い。git 状態の変化（`onGitStatusChange`）や表示設定の変更（`applyDisplayChange`）から呼ばれると、一覧の着地前でも `expandFolder` を発行する。
- 子リストが着地すると `scheduleRebuild` → `applyRows(lastListing == .empty, for: entriesDirectory)`。`hasLoadedEntries` が false なので `isUnchanged` は false になり `setEntries([], …)` が走る。`entries` の didSet で `hasLoadedEntries = true` が立つ。
- これは `reloadExpandedChildren` と `adoptExpansion` の doc が守っている不変条件（一覧の到着前に `hasLoadedEntries` を立てない。previewTarget が `.undetermined` を返せなくなる）と同じもの。

## 再現の形

ツリー表示・変更のみ OFF で窓を開く。git 状態は別 Task で先に着地する（`entriesDirectory == currentDirectory` なので適用される）。ルートの一覧が遅い間に変更のみを ON にする → `revealChangedFolders` → 子リスト着地 → 空の一覧で `setEntries` → サイドバーが「空」を表示し、本物の一覧が届くまでそのまま。

## 方向

`revealChangedFolders` の冒頭に `guard fileListModel.hasLoadedEntries else { return }` を置く。一覧が着地すれば `applyRows` の末尾がもう一度 reveal を呼ぶので、取りこぼしは無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ルートの一覧が着地する前に git 状態と変更のみ ON が適用されても、`hasLoadedEntries` が false のまま（`setEntries` が走らない）テストがある
- [x] #2 一覧が着地した時点でレビュー表示の展開が従来どおり開かれる（既存テストが通る）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: revealChangedFolders に guard fileListModel.hasLoadedEntries を追加。単純化の検討: 新しい状態は足さず既存の hasLoadedEntries を使う。着地時は applyRows 末尾が再度 reveal するので取りこぼし経路は増えない。
検証: 新テスト revealWaitsForRootListing（ルート一覧を AsyncGate で止め、git 状態着地＋変更のみ ON の後に expandedFolderKeys が空・hasLoadedEntries が false、解放後に a が開く）。修正前は expandedFolderKeys.isEmpty で失敗することを実測。swift test 全体 2010+72 件 pass、swiftformat lint 0 件、swiftlint は変更 2 ファイルで 0 件。
テスト fixture の listingGate を gatedFolder 引数（既定 b、空ならルート）で対象を選べるようにした。
viewer-ui.md のレビュー表示「契機」に一覧着地前は開かない旨を追記。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
revealChangedFolders が一覧の着地前に展開を始め、子リストの着地で空の一覧に setEntries が走る問題を、hasLoadedEntries ガード 1 行で塞いだ。着地前の適用を再現するテストを追加し、既存のレビュー展開テストはすべて通過。
<!-- SECTION:FINAL_SUMMARY:END -->
