---
id: TASK-471
title: ファイル切替後の同期区間を SidebarNavigator と SidebarHistoryController で 1 本に畳む
status: To Do
assignee: []
created_date: '2026-08-13 08:11'
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
- [ ] #1 同期区間（フォルダー移動・選択確定・一覧取り直し）が 1 箇所に畳まれ、SidebarNavigator.syncAfterSwitch と SidebarHistoryController.apply の双方がそこを通る
- [ ] #2 TASK-445（選択を同期区間で確定する）と TASK-465（currentDirectory の書き換えは moveCurrentDirectory の 1 経路）の不変条件が、畳んだ後も破れたら落ちるテストで担保されている
- [ ] #3 既存の SidebarNavigatorSyncAfterSwitchTests / SidebarNavigatorHistoryTests / SidebarNavigatorQuickOpenSyncTests が無改変またはそれと同等の網羅で pass する
- [ ] #4 scripts/check-type-group-size.sh --check が pass する
<!-- AC:END -->
