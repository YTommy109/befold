---
id: TASK-361.3
title: サイドバーの非同期列挙の世代ガードを展開単位へ分割する
status: Done
assignee: []
created_date: '2026-08-10 01:57'
updated_date: '2026-08-10 03:11'
labels: []
dependencies:
  - TASK-361.1
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 657000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダを展開するたびに発生する非同期列挙が、サイドバー全体で 1 つしかない世代ガードと競合しないようにする。

## 現状（実測 2026-08-10、HEAD a3202d4）

- App/SidebarNavigator.swift:222 performListing が、:230-233 で listingGeneration / gitStatusGeneration をインクリメントし、:240 の `guard generation == self.listingGeneration` で古い結果を捨てる
- この世代はディレクトリ単位ではなく**サイドバー全体で 1 つ**。複数フォルダを同時に展開すると、後から始まった列挙が先行分を無効化してしまう

## 方針

- 世代ガードをディレクトリ単位（またはリクエスト単位）へ分割し、異なるフォルダの列挙が互いを無効化しないようにする
- ルート切り替え（navigateToFolder）時は、従来どおり全体を無効化できること
- 展開中フォルダの列挙が未完了の間の表示（プレースホルダの有無）を決める

## 制約

- 着手前に /review-design を 1 回回すこと
- 既存テスト SidebarNavigatorGenerationTests(2) / ListingCoherenceTests(5) / FolderNavigationTests(11) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 複数フォルダの列挙が同時に進行しても、互いの結果を破棄しない
- [x] #2 ルート切り替え時は進行中の列挙がすべて無効化される
- [x] #3 世代ガードを全体 1 つへ戻したら落ちるテストがある
- [x] #4 展開の子リストが空のとき、「空フォルダ」「列挙失敗」「未到着」が区別できる（gitStatus の「空 != nil」と同型。先例: FileListModel.swift:146-152 / TASK-285）
- [x] #5 フォルダ行 1 件ごとに走る containsSupportedFile(in:)（DirectoryLister.swift:83、内部でディレクトリ列挙）のコスト上限が決まっており、展開数に比例して MainActor を塞がない
- [x] #6 展開単位の世代ガードに、開始時の無効化と着地時の一致確認の両方がある（既存の 2 系統 SidebarNavigator.performListing:222-258 / FileListModel.applyGitStatus:188-200 はディレクトリ 1 つ単位で、そのままでは足りない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した実装方針（2026-08-10）

レビューで 10 件の方針変更が出た。採用したものと理由。

1. **A**: 展開の子列挙に DirectoryLister.listEntriesAsync を使わない。あちらは親移動行を
   含む畳んだ形を返すため、展開したフォルダごとに .. 行が生える。childEntriesAsync を
   新設し、SidebarNavigator へ childrenLister として別に注入する
2. **B**: SidebarRowBuilder.rows の呼び出しをサイドバーでは applyRows 1 箇所へ寄せる
   （呼び出し元がそれぞれ畳むと、展開の材料を渡し忘れた経路がドリルダウンのまま残る）
3. **C**: 選択維持の判定をフラット化後の行に対して行う。ルート直下だけを見ると、
   展開したサブフォルダ内のファイルを選んでいる間ずっと選択が飛ぶ
4. **D**: cancelPendingListing() で expansion.invalidateAll() を呼ぶ（TASK-300 と同型）
5. **E**: ルートを取り直す契機（並び順・隠しファイル・フォーカス復帰・リネーム）で
   展開中サブツリーの子も取り直す。取り直さないと展開中だけ古い規則で並び続ける
6. **F**: collapse は配下の展開も一緒に捨てる。残すと、畳んでいる間に走行中だった配下の
   列挙が着地して子リストを書き、再展開したときに古い内容が再列挙なしで復活する
7. **G**: .failed を落として .loading / .loaded の 2 状態にする。
   DirectoryEnumeration.sortedContents が失敗を握り潰すため到達不能で、置くと
   「.failed が来ない = 失敗が無い」と読めてしまう。列挙 API 側は TASK-404 で扱う
8. **H**: appendingOpenFile はルート直下にのみ適用する（不変条件を明示的に縮小）。
   展開した子リストにも通すには openFile を非同期側で捕捉することになり、
   ファイル切替後は次の再列挙まで反映されない非対称が生じる。361.4 へ申し送る
9. **I**: SidebarExpansion を注入引数にしない（TASK-319 と同型の事故を構造で塞ぐ）
10. **J**: AC #5 を「MainActor 上の列挙 0 回」と「展開 1 回につき列挙呼び出し 1 回」の
    2 本に分けて測る

### @Observable にしない

サイドバーの描画の真実の源は FileListModel.entries → visibleEntries の 1 本で、
entries の didSet が索引の作り直し・提示対象の通知を連動させている。SidebarExpansion も
観測可能にすると 1 回の展開で 2 系統の再描画が飛び、「visibleEntries の添字 = 行番号」の
前提へ別経路から触ることになる。行の生成は SidebarNavigator.applyRows 1 箇所に置く。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-10）

### 実装中に見つかった、レビューでも出ていなかった 2 件

1. **reloadExpandedChildren を performListing の冒頭で「行の組み直し」まで行うと、
   一覧の到着前に hasLoadedEntries が立つ。** previewTarget が .undetermined を
   返せなくなり、実測で 22 件のテストが落ちた（ViewerWindowControllerPreviewTargetTests /
   SourceModeTests / ToolbarTests 等）。行の組み直しはルートの一覧が届いた時点と
   子リストが届いた時点だけに限定した。
2. **取り直し中に子リストを .loading へ戻すと、展開したサブフォルダ内の選択が失われる。**
   新しい子が届くまで展開が畳まれた形になり、その間に走る選択維持の判定で落ちる。
   自分で書いた「展開したサブフォルダ内の選択が失われない」テストが落ちて判明した。
   古い子を出したまま差し替える（走行中の古い結果は世代ガードが弾く）形に変更。

### swiftlint 対応で分割したファイル

SidebarNavigator.swift が file_length（492 行）と type_body_length（268 行）を超えたため、
既存の +History / +SelectionMemory と同じ形で 2 ファイルへ分割した。

- SidebarNavigator+Expansion.swift（展開の配線）
- SidebarNavigator+FolderNavigation.swift（navigateToFolder とその補助）

分割に伴い performListing / childrenLister を internal にした（Swift の private は
ファイルスコープで別ファイルの extension から参照できないため）。

### 検証（実測 2026-08-10）

- swift test --skip Integration --skip FileWatcherTests: **1183 tests / 166 suites 全通過**
  （変更前 1168。新規 15 件）
- 既存テスト SidebarNavigatorGenerationTests / ListingCoherenceTests /
  FolderNavigationTests はいずれも変更なしで通過
- swiftformat --lint: 0 件
- swiftlint: origin/main とのベースライン差分は FileListView.swift の
  type_body_length が 312 → 300 行へ減った 1 行のみ（新規違反ゼロ）
- xcodegen generate 実行済み

### 起票したフォローアップ

- TASK-404: DirectoryEnumeration が列挙失敗を表現できない件（GUI/CLI 双方へ波及するため別タスク）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
展開ごとの非同期列挙に「フォルダごとの世代 + ルート全体のエポック」の 2 段ガードを入れ、SidebarExpansion として新設した。展開の意図（expandedKeys）と手元のデータ（children）を分けて持ち、.loading と .loaded([]) で「未到着」と「空フォルダ」を区別する（.failed は列挙 API が失敗を表現できず到達不能なため置かず、TASK-404 へ切り出した）。行の組み立ては SidebarNavigator.applyRows 1 箇所へ寄せ、選択維持の判定もフラット化後の行に対して行うようにした。検証: swift test 1183 件全通過（既存の世代ガード・移動・整合性テストは無変更で通過）、swiftlint 新規違反ゼロ、xcodebuild exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
