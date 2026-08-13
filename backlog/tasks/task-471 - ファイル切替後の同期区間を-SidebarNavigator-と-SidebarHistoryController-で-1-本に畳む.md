---
id: TASK-471
title: ファイル切替後の同期区間を SidebarNavigator と SidebarHistoryController で 1 本に畳む
status: Done
assignee: []
created_date: '2026-08-13 08:11'
updated_date: '2026-08-13 10:38'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 114900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator.syncAfterSwitch と SidebarHistoryController.apply が、同じ「切替後の同期区間」——moveCurrentDirectory で表示中フォルダーを動かす → 選択をその区間で確定する → refreshFileList で取り直す——を別々に書いている。後者のコメント（SidebarHistoryController.swift:107）自身が「SidebarNavigator.syncAfterSwitch と同じ理由 / TASK-445」と相互参照しており、同型であることは記録済み。片方だけを直すと兄弟に穴が残る形（CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に該当する予備軍）。TASK-436 の PR で type-group-size 超過を解消する際の設計レビューで、SidebarNavigator の切り出し先を探して見つかった論点。そのときは影響範囲が履歴適用の振る舞いに及ぶため、述語 1 本を FileListModel へ移す最小案を採り、統合はこのタスクへ切り出した。畳めれば SidebarNavigator グループ（現在 388 行 / 閾値 400）にも余裕が生まれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同期区間（フォルダー移動・選択確定・一覧取り直し）が 1 箇所に畳まれ、SidebarNavigator.syncAfterSwitch と SidebarHistoryController.apply の双方がそこを通る
- [x] #2 TASK-445（選択を同期区間で確定する）と TASK-465（currentDirectory の書き換えは moveCurrentDirectory の 1 経路）の不変条件が、畳んだ後も破れたら落ちるテストで担保されている
- [x] #3 既存の SidebarNavigatorSyncAfterSwitchTests / SidebarNavigatorHistoryTests / SidebarNavigatorQuickOpenSyncTests が無改変またはそれと同等の網羅で pass する
- [x] #4 scripts/check-type-group-size.sh --check が pass する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
同期区間(フォルダー移動 → 選択確定 → 一覧取り直し)を新設の SidebarPostSwitchSync.apply(on:movingTo:selecting:refreshesWhenStaying:) へ畳んだ。SidebarNavigator.syncAfterSwitch は「動かすかどうか」の判定(isReachableInCurrentListing)と recordHistory だけを残し、SidebarHistoryController.applyEntry は selection を一切書かなくなった(applySelection を撤去。型 doc も「fileListModel を読むだけで書かない」へ更新)。

SidebarNavigator のメソッドではなく別型にしたのは type-group-size のため。SidebarNavigator グループは 388/400 で、フォールドをメソッドとして置くと doc 込みで約 414 行になり閾値超過だった。別型にしたことでグループは 386 行へ減った。

applyEntry では navigator の guard を performFileSwitch より前へ移した。従来は navigator が nil でも選択だけ書いて true を返していたため、切替済み・同期区間未通過の部分適用になりうる形だった。

不変条件の担保(AC#2)は新規 SidebarPostSwitchSyncTests の 4 本。ファイル切替・履歴適用の両入口について (a) awaitSettled を挟まずに選択が確定していること(TASK-445)、(b) 移動後に展開が捨てられていること(= moveCurrentDirectory を通った証跡 / TASK-465)を見る。実測でミューテーションを 2 種入れて確認した — 区間内の confirmSelection を削ると (a) の 2 本だけが落ち、moveCurrentDirectory を currentDirectory への直接代入に置き換えると (b) の 2 本だけが落ちる(いずれも両入口が同時に落ちる)。

検証: swift test 全体 1499 tests / 236 suites pass。scripts/check-type-group-size.sh --check pass。swiftformat fix 後の差分なし、swiftlint は変更 3 ファイルで警告 0 件。既存の SidebarNavigatorSyncAfterSwitchTests / SidebarNavigatorHistoryTests / SidebarNavigatorQuickOpenSyncTests は無改変で pass(AC#3)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
切替後の同期区間を SidebarPostSwitchSync へ 1 本化し、SidebarNavigator.syncAfterSwitch と SidebarHistoryController の履歴適用の双方がそこを通るようにした。TASK-445 / TASK-465 の不変条件は、両入口について破れたら落ちるテスト 4 本で担保(ミューテーション 2 種で実際に落ちることを実測)。swift test 1499 件 pass、type-group-size --check pass。
<!-- SECTION:FINAL_SUMMARY:END -->
