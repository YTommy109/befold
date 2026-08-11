---
id: TASK-410
title: ルート一覧・Quick Open の列挙失敗を「空」と区別して伝える
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 06:25'
updated_date: '2026-08-11 12:34'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-404 で `DirectoryEnumeration.sortedContents` は列挙失敗を nil で表現できるようになり、ツリー展開（子リスト）は `.failed` として空フォルダと区別するようになった。

一方、次の 3 経路は **失敗を明示的に空へ畳んだまま**にしてある（TASK-404 のスコープ外）。畳んだ理由はそれぞれの呼び出し箇所の doc コメントに書いてある。

## 対象と現状

1. **サイドバーのルート一覧** — `DirectoryLister.buildEntries` が `childEntries(...) ?? []`。ルート一覧には失敗を出す先が無い（開閉三角は子フォルダの行にしかない）ため空へ畳んでいる。
2. **プレビューのフォルダー一覧** — `FolderListingView` の `.task` が `listEntriesAsync` を使う。`cachedEntries` は既に「nil = 未到着 / [] = 空」の区別を持っており、そこへ失敗を `[]` として流すと `SidebarEmptyState` が「空のフォルダー」と言い切る。既存の区別を壊す方向に落ちている。
3. **Quick Open のパスモード** — `DirectoryLister.allEntriesSorted` が `?? ([], [])`。候補 0 件が「該当なし」と区別できない。

## 参考

- 判断の記録は TASK-404 の Implementation Notes（`/review-design` の結果）
- `DirectoryEnumeration.sortedContents` の doc（失敗と空の意味の違い）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `FolderListingView` が列挙失敗を「空のフォルダー」として表示しない
- [x] #2 サイドバーのルート一覧で、列挙に失敗したディレクトリを開いたときに空一覧として確定表示しない
- [x] #3 Quick Open のパスモードで、列挙失敗と候補 0 件が区別される（区別しないと決める場合は理由を Notes に残す）
- [x] #4 3 経路それぞれについて、失敗時の表示をユニットテストまたは純粋関数のテストで固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化の検討（実装前）

失敗を運ぶ専用の経路を 3 本作るのではなく、**既に理由で文言を出し分けている
SidebarEmptyState / SidebarEmptyReason に 1 ケース足す**ことで、経路①ルート一覧と
経路②プレビューを同じ実装で解決する（両者は既に同じ空状態 View を共有している）。
増える状態は「列挙に失敗したか」の Bool 1 本で、新しい表示設定・永続化は増やさない。

listEntriesAsync を Optional 戻りにする案は採らない。失敗時も親移動行と
appendingOpenFile の行（いま開いている文書）は出す必要があり、nil にすると
その経路ごと落ちる（DirectoryLister.swift:90-95 の既存 doc の理由）。

## 実装

1. DirectoryLister に `DirectoryListing { entries: [FileListEntry]; didFail: Bool }` を
   追加し、listEntries / listEntriesAsync の戻りをこれにする。buildEntries の
   `childEntries(...) ?? []` は畳んだ事実を didFail に記録する形へ置き換える。
2. SidebarEmptyReason に `.enumerationFailed` を追加（文言キー
   sidebar.empty.enumerationFailed(.description)）。reason(...) に didFail を
   **必須引数**で足し、失敗を最優先で確定する（SidebarDisclosure.state と同じ順序規則）。
   SidebarEmptyState にも必須引数で足す（デフォルト引数を付けない = 2 呼び出し元の
   渡し忘れがコンパイルエラーになる）。
3. 経路①: FileListModel に didFailListing を持たせ、setEntries と同じ 1 経路で代入する。
   SidebarNavigator.performListing の onApplied が DirectoryListing を渡す。
   FileListView.emptyStateView が model から渡す。
4. 経路②: FolderListingView.cachedEntries と FolderListingSource.shared の中身を
   DirectoryListing? にする。.shared 側もサイドバーの失敗フラグを運ぶ（片側だけ直すと
   TASK-320 と同型の取り残しになる）。
5. 経路③: allEntriesSorted を [URL]? に、QuickOpenEnvironment.directoryEntries も [URL]? に。
   QuickOpenModel は失敗時に quickOpen.noMatches ではなく新キー
   quickOpen.enumerationFailed を出す（「一致なし」と「読めない」で利用者の次の行動が違う）。
6. Localizable.xcstrings へ 3 キー追加（キー順ソートはしない。近縁キーの直後へ挿入）。

## テスト（AC#4）

- SidebarEmptyStateTests: reason が失敗を絞り込みより優先して .enumerationFailed にする。
- DirectoryListerEnumerationFailureTests: 既存 listEntriesFoldsFailureIntoEmptyList を
  「失敗で didFail = true、空ディレクトリでは false」へ書き換え、親移動行が残ることも固定。
- FolderListingViewFilterTests: 失敗した一覧が .noSupportedFiles にならない。
- SidebarNavigator 系: ルート列挙失敗が fileListModel.didFailListing へ届く。
- QuickOpenModelTests: directoryEntries が nil のとき、0 件と別の通知になる。

## /review-design の結果（実装前・計画へ反映済み）

A. **型グループのラチェットに抵触する**（CI の type-group-size が exit code で落とす:
   .github/workflows/ci.yml:80-103）。実測でベースライン登録済みなのは FileListModel 459 /
   FileListView 437 / SidebarNavigator 611 / QuickOpenModelTests 452。
   → 空状態の入力を SidebarEmptyState.swift 側の `SidebarEmptyContext` へ集約し、
   FileListView は 4 引数ではなく 1 値を渡す（行数は減る）。FileListModel の
   activeGitChangeFilter も context 側へ寄せて相殺する。新規 QuickOpen テストは
   QuickOpenModelTests へ足さず新ファイルに置く。コミット前に --check で実測確認する。
B. FolderListingSource のカスタム == （FolderListingView.swift:20-27）に didFail を
   明示的に足す。落とすと失敗→成功で行 ID が同じ（どちらも空）のとき再描画されない。
C. 文言は新設せず、既存キー sidebar.tree.enumerationFailed を空状態の見出しへ再利用する。
   追加は説明文 sidebar.empty.enumerationFailed.description の 1 件のみ。
   シンボルは行と揃えて exclamationmark.triangle。
D. 「失敗なら必ず失敗表示が出る」は成り立たない。appendingOpenFile が開いている文書の行を
   足すため一覧が空にならないことがある（FolderListingView.swift:145 の出現条件）。
   オーバーレイの出現条件は変えず、出るときの理由だけを失敗優先にする。
E. QuickOpenModel は失敗を stored property で持たず、apply(_:listingFailed:) の
   **必須引数**にする（QuickOpenModel.swift:176-196 の 3 分岐すべてが apply を通るため、
   別 var にすると .empty / .fuzzy で前回の失敗が残る）。showsNoMatches に !listingFailed を足す。

別タスク: DirectoryLister.containsSupportedFile(:157-159) の失敗畳み込み（読めないフォルダが
「開けるものが無いフォルダ」と同じ見た目になる）は本タスクの 3 経路外。実装後に起票する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

失敗を運ぶ経路を 3 本作らず、既に理由で文言を出し分けている SidebarEmptyState /
SidebarEmptyReason に `.enumerationFailed` を 1 ケース足すことで、経路①（ルート一覧）と
経路②（プレビュー）を同じ実装で解決した。両者は既に同じ空状態 View を共有していたため、
新設したのは「列挙に失敗したか」の Bool 1 本だけで、表示設定・永続化は増えていない。

## /review-design の結果（5 件を実装へ反映）

A（項目 10）: 型グループのラチェット（CI: .github/workflows/ci.yml:80-103）に抵触することを
実装前に検出した。FileListModel 459 / FileListView 437 / SidebarNavigator 611 /
QuickOpenModelTests 452 が登録済み。→ 空状態の入力を SidebarEmptyContext へ集約して
FileListView を 4 引数 → 1 値に減らし（-4）、FileListModel の activeGitChangeFilter を
context 側へ移して相殺（-2）。SidebarNavigator は rebuildRows を
DirectoryListing.filteringEntries の 1 行へ畳んで ±0。Quick Open の新規テストは
QuickOpenModelTests へ足さず QuickOpenPathModeFailureTests.swift を新設。
最終実測: `scripts/check-type-group-size.sh --check` = exit 0（減った 2 グループは
--update-baseline で締め直した）。
B（項目 2）: FolderListingSource の == に didFailEnumeration を含めた。行 ID だけの比較では
「読めなかった」と「空だった」がどちらも 0 行で等しくなり、遷移で再描画されない。
C（項目 4）: 文言は新設せず、ツリーの失敗行と同じキーを共有する形にした
（sidebar.tree.enumerationFailed → folder.enumerationFailed へ改名し 3 箇所で共有、
追加は description 1 件のみ）。
D（項目 1・4）: 「失敗なら必ず失敗表示が出る」は成り立たない。appendingOpenFile が
開いている文書の行を足すため一覧が空にならないことがある。オーバーレイの出現条件は
変えず、出るときの理由だけを失敗優先にした。
E（項目 9）: QuickOpenModel は失敗を別 var で持たず apply(_:listingFailed:) の必須引数に
した。refresh() の 3 分岐すべてが apply を通るため、別 var だと .empty / .fuzzy へ戻った
ときに前回の失敗が残る。

## 決めたこと（記録）

- listEntriesAsync を Optional 戻りにはしない。失敗時も親移動行と「いま開いている文書」の
  行は出す必要があり、nil にするとその経路ごと落ちる。「開いている文書は必ず一覧に含める」は
  列挙の成否に関わらず保つ不変条件として DirectoryListing の doc に書き、
  DirectoryListerEnumerationFailureTests.failedListingStillAcceptsOpenFile で固定した。
- 失敗の事実を書き写す経路を作らない。行を加工する側は replacingEntries /
  filteringEntries を通し、FileListModel の didFailListing は setEntries の 1 本でしか
  更新されない（SidebarListingFailureTests.rebuildingRowsKeepsFailure が担保）。

## 検証（実測）

- `swift test --skip Integration --skip FileWatcherTests`: **1305 tests / 183 suites passed**。
- `xcodebuild build -scheme befold -quiet`: exit 0（新規 4 ファイルの xcodegen 反映込み）。
- swiftlint: origin/main を別ディレクトリへ git archive して比較し、**ベースライン差分ゼロ**
  （双方 71 件）。途中 DirectoryListerTests の type_body_length が 261→263 になったため、
  閾値を緩めず 2 行を 1 行へ畳んで解消した。
- swiftformat: fix モードを 1 回流したあと `-- --lint` で 0 件。
- 型グループ: `scripts/check-type-group-size.sh --check` exit 0。

## 途中で見つけた落とし穴

SidebarNavigator は host を weak 参照するため、テストが host を捨てると
refreshFileList の `guard host != nil` で列挙自体が走らず、**何も測らないまま通る**。
新規テストで実際にこれを踏んだので、SidebarListingFailureTests の型 doc に記録した。

## AC の裏付け

- AC#1: SidebarListingFailureTests.ownListingKeepsFailure（自前列挙の失敗が空一覧へ畳まれない）
  と sharedListingCarriesFailure（サイドバー供給の一覧にも失敗が乗る）。
  文言の割り当ては SidebarEmptyStateTests.reportsEnumerationFailure /
  enumerationFailureWinsOverFilters。
- AC#2: SidebarListingFailureTests.rootListingFailureReachesEmptyState（本番経路で
  失敗が空状態の理由まで届く）と emptyRootListingKeepsNoSupportedFiles（読めて空だった
  場合は従来どおり）。
- AC#3: 区別する側を採用。QuickOpenPathModeFailureTests の 3 件
  （失敗と 0 件の出し分け・読めた 0 件は従来どおり・次の入力で失敗が残らない）。
- AC#4: 3 経路それぞれに上記のテストがあり、いずれも純粋関数か注入したスタブで
  決定的に測っている（列挙失敗の注入は存在しないディレクトリと nil を返すスタブ）。

## 残した申し送り

DirectoryLister.containsSupportedFile は列挙失敗を false に畳むため、読めないフォルダが
サイドバーで「開けるものが無いフォルダ」と同じ見た目になる。本タスクの 3 経路の外なので
別タスクとして起票する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ルート一覧・プレビュー・Quick Open の 3 経路が列挙失敗を「空」へ畳んでいたのをやめ、失敗を「読み取れませんでした」として伝えるようにした（TASK-404 の申し送り）。

中核は DirectoryListing（行 + 列挙に失敗したか）で、行を Optional にしない点が要点。失敗しても親移動行と「いま開いている文書」の行は出す必要があり、nil にするとその不変条件ごと落ちるため、失敗の事実だけを別に運ぶ。行を加工する経路は replacingEntries / filteringEntries を通すので、加工のたびに失敗フラグを書き写して false へ戻す事故が起きない。

表示は、サイドバーとプレビューが既に共有していた SidebarEmptyState へ .enumerationFailed を 1 ケース足して両経路を同時に解決した。入力は SidebarEmptyContext へ集約し、増えたときに片側の呼び出し元だけが古い形で残らないようにした。文言はツリー展開の失敗行と同じキー（folder.enumerationFailed）を共有する。Quick Open は失敗を stored property ではなく apply(_:listingFailed:) の必須引数にして、fuzzy へ戻ったときに前の失敗が残らない形にした。

実装前に /review-design を回し、5 件（型グループのラチェット抵触・== への失敗の反映漏れ・文言の二重化・失敗表示が必ず出るという誤った前提・Quick Open の失敗フラグの持ち方）を反映してから着手した。

検証: swift test 1305 件通過、xcodebuild exit 0、swiftlint ベースライン差分ゼロ（双方 71 件）、swiftformat 0 件、型グループのラチェット exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
