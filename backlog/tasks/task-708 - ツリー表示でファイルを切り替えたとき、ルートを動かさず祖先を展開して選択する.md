---
id: TASK-708
title: ツリー表示でファイルを切り替えたとき、ルートを動かさず祖先を展開して選択する
status: Done
assignee: []
created_date: '2026-10-16 13:31'
updated_date: '2026-10-16 14:12'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarNavigator.swift
  - BefoldApp/befold/App/SidebarLayoutTransition.swift
  - BefoldApp/befold/App/QuickOpenCoordinator.swift
  - BefoldApp/befold/Viewer/FileListModel.swift
priority: medium
type: bug
ordinal: 897000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ツリー表示でクイックオープン(⌘P)からファイルを開くと、そのファイルの親フォルダーへ表示ルートが移動し、それまでの展開状態も全て破棄される。期待は、ルートを動かさずに祖先フォルダーを展開して当該ファイルを選択・スクロールすること。原因は SidebarNavigator.syncAfterSwitch が FileListModel.isReachableInCurrentListing(行の有無)で移動を判定していること。ツリーでは畳まれたフォルダー配下のファイルは行に存在しないため「到達不可」とされ moveCurrentDirectory が走る(ツリー表示中は discardExpansion も走る)。SidebarLayoutTransition.revealSelection(under:) が祖先展開+スクロール要求を既に持っており流用できる。仕様: ツリー表示でファイルがルート配下なら移動せず展開して選択。ルート外なら従来どおり親フォルダーへ移動。リスト表示(drill-down)は現状維持。履歴の戻る/進む(SidebarPostSwitchSync 直接経路)は触らない。syncAfterSwitch を通る全経路(クイックオープン・リンク・CLI)に適用する。着手前に /review-design を回す(既存の共通経路に触るため)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツリー表示で、ルート配下の畳まれたフォルダー内のファイルを switchFile すると currentDirectory が変わらない
- [x] #2 同条件で祖先フォルダーが全て展開され、他に開いていたフォルダーの展開は維持される
- [x] #3 同条件で選択がそのファイルになり、行が可視になるようスクロールされる(実機で深い階層を確認。行の着地が遅れても効くこと)
- [x] #4 ツリー表示でルート外のファイルは従来どおり親フォルダーへ移動する。リスト表示の挙動は変わらない
- [x] #5 revealSelection(under:) をレイアウト切替と syncAfterSwitch で共有し、実装を重複させない
- [x] #6 上記の回帰テストがあり、実装を戻すと落ちることを確認する
- [x] #7 隠しフォルダー配下(showHiddenFiles OFF)で行が出ない場合の挙動を確認し、結果を Notes に残す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー(/review-design)結果。1 判定の真実の源: 隠し判定はルート直下の祖先フォルダー行の実在(一覧組み立てが chflags 込みで判定済み)を事実源にし、深い階層はドット始まりのみ(chflags 深層は未対応・既知の限界)。2 不変条件: 同期区間の選択確定は SidebarPostSwitchSync.apply を通し、revealSelection は選択を変えない。3 消費経路: syncAfterSwitch の呼び出し元は ViewerWindowController+FileNavigation 1 箇所のみ(rg 実測)で、判定は syncAfterSwitch に集約。4 表示: 新しい空状態なし。5 順序: 展開はルート一覧の着地後(revealSelection の既存設計)。6 高頻度経路ではない。7 テスト: 回帰テストは判定を無効化すると落ちることを実測。8 世代管理: refreshFileList の世代ガードに乗る。9 粒度: 該当なし。10 SidebarNavigator 型グループは 448 行、stored property・プロトコル準拠の増加なし、private メソッド 1 本の追加のみ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: SidebarNavigator.syncAfterSwitch で、ツリー表示かつ切替先が currentDirectory 配下なら moveCurrentDirectory せず layoutTransition.revealSelection(under:) を呼ぶ(private を外して共有)。回帰テスト SidebarNavigatorSyncAfterSwitchTests に 2 本追加、判定を無効化すると落ちることを確認。SidebarPostSwitchSyncTests のフィクスチャ outside が base 配下だったため base 外へ移した。swift test 全体 2058 件 pass。未了: AC #3(実機で深い階層のスクロール確認)と AC #7(showHiddenFiles OFF の隠しフォルダー配下。現状は展開は走るが行が無く、選択のみでスクロールされない見込み・未検証)、/review-design は未実施。

AC #7 実測: showHiddenFiles OFF の隠しフォルダー配下へ切り替えると、行が無いまま選択だけが付き previewTarget が .folder(ルート) に落ちた(TASK-445 と同型)。そのため隠しフォルダー経由は従来どおり親へ移動に倒し、回帰テスト treeHiddenAncestorMoves を追加。AC #3(実機での深い階層スクロール)は未確認で、実機確認が必要。

AC #3 実機相当の実測(2026-10-16): Debug ビルドを tree 表示で起動し、ルート直下に 60 フォルダー + d60/x/y/z/target.md の fixture を用意。00-root.md 本文のリンク(syncAfterSwitch 経由)を CGEvent でクリック。AX で測定: 行数 66(ルートの一覧のまま・currentDirectory 不変)、d60/x/y/z が展開され d01〜d59 は畳んだまま、選択は target.md、行 y=1048 がサイドバー可視領域(y 166〜1080)内。展開前の同行は 60 行目以降(y>1900 相当)で、スクロールされたことを示す。docs/dev に syncAfterSwitch の挙動記述は無く、現在仕様の更新は不要。

AC #3 補足(2026-10-16): (a) 切替前後の実測。切替前は d01 y=166(最上部)・選択 00-root.md が y=2086(画面外)、切替後は d01 y=-968(1134 スクロール)・選択 target.md が y=1048(可視範囲 166〜1080 内)・行数 61→66。ルートは不変。(b) 遅延着地: SidebarNavigatorSyncAfterSwitchTests.treeRevealScrollsEvenWhenChildrenLandLate を追加。子リストの列挙に 200ms の遅延を入れ、着地前は行が無くスクロール要求なし、着地後に spy へ scrollRowToVisible(行番号)が来ることを検証。SidebarTableFocuser.retryPendingScroll を無効化すると落ちることを確認(再試行の保持要求が効いている)。なお revealSelection 内の『fileListModel.selection = fileListModel.selection』を外してもこのテストは通る(選択の確定書き込みが保持要求を積むため)。冗長だが既存のレイアウト切替経路の挙動のため触っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー表示で、ルート配下の畳まれたフォルダー内のファイルへ切り替えても currentDirectory を動かさず、祖先を展開して選択・スクロールするよう SidebarNavigator.syncAfterSwitch を変更(revealSelection を SidebarLayoutTransition と共有)。ルート外・隠しフォルダー経由・リスト表示は従来どおり移動。回帰テスト 3 本を追加し、判定を無効化すると落ちることを確認、swift test 全 2059 件 pass。実機相当(Debug ビルド + AX)で深い階層の展開・選択・可視化を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
