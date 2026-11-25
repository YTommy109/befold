---
id: TASK-930.6
title: ファイル切替の失敗時、サイドバーの選択を本文の意図に合わせて戻す
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T13:13:58Z'
updated_date: '2026-11-25T13:24:12Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25)。ViewerWindowController.switchFile の .failed 分岐は sidebar.restoreSelection(to: oldURL) で開いている文書の行へ選択を戻す。提示を選択から導いていた頃は正しかったが、ADR 0013 以降はフォルダー一覧を出している間(意図 .folder(X))も文書の行が強調される。TASK-930.3 で SidebarListingCoordinator から取り除いたのと同じ不整合(提示していない行が光り、表示形式の切り替えでカレントが文書の親へ移る)。再現手順(未実測): フォルダー X の一覧を出す → Finder で X/a.md を削除 → 取り直し前に本文の一覧の a.md を押す → 切替が失敗し、本文は X の一覧のまま文書の行が強調される。コード上の該当は確認済み、実機・テストでの再現は未実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー一覧の表示中にファイル切替が失敗したとき、選択は意図に合う値(表示中フォルダー自身の一覧なら nil、フォルダー行ならその URL)へ戻り、文書の行は強調されない
- [x] #2 その状態で表示形式を切り替えても currentDirectory が文書の親へ移らないことをテストで確かめる
- [x] #3 修正を戻すとテストが落ちることを確かめる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
SidebarNavigator.restoreSelection(to: oldURL) を、窓の意図を読んで戻し先を決める形へ変える(呼び出し元は switchFile の .failed 1 か所)。フォルダー一覧なら表示中フォルダー自身は nil、フォルダー行はその URL、文書なら開いている文書。SidebarNavigator は例外上限 411 に張り付いているため、置き場は切替直後の選択を確定する SidebarPostSwitchSync にする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: SidebarNavigator.restoreSelection(to:) を撤去し、SidebarPostSwitchSync.restoreSelection(on:) を足した。host.presentedTarget を読み、フォルダー一覧なら表示中フォルダー自身の一覧は nil・フォルダー行はその URL、文書なら host.currentFileURL へ戻す。置き場を navigator にすると型グループが 419 行(例外上限 411)を超えたため、切替直後の選択を確定する唯一の場所である SidebarPostSwitchSync へ移した(navigator は 406 行、例外表を実測値へ更新)。
再現: 新規テスト ViewerWindowFileOpenPresentationTests.failedSwitchRestoresSelectionMatchingIntent(ツリー/リスト × フォルダーに入った / フォルダー行を選んだ)を修正前のコードで実行し、4 ケースすべてで選択が文書の行になり、うち 1 ケースで表示形式の切り替えにより currentDirectory が文書の親へ移ることを実測した。修正後は通り、修正を戻す変異で 4 ケースすべてが落ちる。
検証: swift test --skip PDF 2008 件通過。swiftlint は変更ファイルで 0 件。型グループの --check 通過。xcodebuild は .build/xcode の開発ビルドが起動中のため別の derivedDataPath で成功を確認。実機確認は未実施。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダー一覧の表示中にファイル切替が失敗したとき、サイドバーの選択を開いている文書の行ではなく本文の意図に合わせて戻すようにした(SidebarPostSwitchSync.restoreSelection(on:))。修正前は提示していない文書の行が強調され、表示形式の切り替えでカレントが文書の親へ移っていた(テストで実測)。検証: 新規テスト 4 ケース(変異で全落ち)、全体 2008 件通過、xcodebuild 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
