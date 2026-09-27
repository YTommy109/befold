---
id: TASK-639
title: revealChangedFolders がフォルダー移動中に移動先のキーで旧ディレクトリの git 状態を適用する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 06:23'
updated_date: '2026-09-27 06:51'
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
- [x] #1 reveal の適用先キーは着地済みの一覧のディレクトリ（`entriesDirectory` / `applyRows` の `directory`）から作られ、`currentDirectory` だけが先に進んだ状態では reveal が走らない
- [x] #2 移動中に旧ディレクトリの子リストが着地するケースをテストで再現し、移動先の展開集合が移動先の git 状態だけから求めた集合と一致する（旧状態由来の余分なキーが無い）
- [x] #3 `.toggleChangedFilesOnly` 経路でも同じ判定が使われている（経路を分けない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `revealChangedFolders` の適用先キーを `entriesDirectory` から作り、`currentDirectory` と一致しない間（移動中 = 一覧の着地前）は何もしない。移動先は `applyRows` → `setEntries` → 保留 git 状態の昇格 → didSet の順で着地するので、そこで全件 reveal が 1 回走る。3 呼び出し点は同じ関数を通るので経路は分けない。
2. テスト（SidebarNavigatorReviewExpansionTests）: 移動先の一覧取得をゲートで止め、移動中に「変更のみ」を ON にする経路で再現する。移動前の git 状態（b/c/y.md）と移動後の状態（b/d/z.md）を変え、移動先の展開集合が移動後の状態だけから求めた [b/d] になることを確認する。修正前は移動前の状態で b/c も開き [b/c, b/d] になる。
review-design: 既存の判定に guard を 1 つ足すだけで状態・経路は増えない（1 ファイル内の局所修正）。項目 8 の「着地時の一致確認」に当たる修正で、開始時の無効化は moveCurrentDirectory の discardExpansion が既に担う。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- `revealChangedFolders` の適用先キーを `entriesDirectory` から作り、`currentDirectory` と一致しない間（移動中 = 一覧の着地前）は何もしない guard を 1 つ足しただけ。状態・経路は増えていない。3 呼び出し点はすべてこの関数を通るので `.toggleChangedFilesOnly` 経路も同じ判定になる。
- 移動先は `performListing` → `applyRows` → `setEntries` → 保留 git 状態の昇格 → didSet の順で着地する（変更のみ ON では git 結果の反映が `onApplied` の直前に同じタスクで走るため、着地時点で移動先の状態が保留されている）。そこで全件 reveal が 1 回走る。開始時の無効化は `moveCurrentDirectory` の `discardExpansion` が既に担う。
- review-design: 1 ファイル内の局所修正（guard 1 行）で状態・経路を増やさないため回していない。責務レビューも同様に不要。

## 検証
- 新テスト `SidebarNavigatorReviewExpansionTests.moveInFlightRevealsOnlyFromLandedStatus`: 移動先 `b` の一覧を `AsyncGate` で止め、移動中に git 状態を b/c/y.md → b/d/z.md へ変えて「変更のみ」を ON にし、ゲートを開いて着地させる。修正後は展開集合が [b/d]。guard を外すと Expectation failed: expandedFolderKeys == [fixture.key("b/d")] で落ちる（移動前の状態で b/c も開く）ことを実測。
- `swift test --skip Integration --skip FileWatcherTests`: 1886 + 66 件 pass。`xcodebuild build` 成功。swiftlint は origin/main と差分ゼロ（46 → 46）。swiftformat lint 0 件。型グループ: SidebarTreePresenter 291 行（閾値内）。
- native-app-design.md / viewer-ui.md への反映は不要（規則・契機・解除の記述は変わらず、移動中に走らないのは既存の「着地点で拾う」記述の範囲内）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`revealChangedFolders` の適用先を着地済みの一覧のディレクトリ（`entriesDirectory`）にし、`currentDirectory` だけが先に進んでいる移動中は何もしないようにした。移動先の一覧が着地した時点で移動先の git 状態による全件 reveal が 1 回走る。移動中に「変更のみ」を ON にする経路を AsyncGate で再現するテストを足し、guard を外すと落ちることを実測。全件テスト 1886 + 66 pass、xcodebuild 成功、swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
