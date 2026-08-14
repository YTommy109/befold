---
id: TASK-480.3
title: サイドバー表示の操作経路をアクティブウィンドウのみへ向ける
status: To Do
assignee: []
created_date: '2026-08-14 08:02'
labels: []
dependencies:
  - TASK-480.2
parent_task_id: TASK-480
priority: high
type: task
ordinal: 90300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GlobalDisplayBroadcaster からサイドバー表示 4 値の一括反映を外し、操作経路をアクティブウィンドウ 1 つへ向ける。対象の経路は次のとおり。

- メニュー(View メニューの ⌃⌘T / 不可視ファイル / 変更ファイルのみ / 並び順)と AppDelegate の @objc アクション、および validateMenuItem のチェック状態
- サイドバーヘッダーのアイコンボタン(SidebarHeaderControlsModel 経由)
- CLI の --hidden-files / --no-hidden-files(setHiddenFiles)。CLI 起動時に開く対象ウィンドウへ適用する形にする

GlobalDisplayBroadcaster の doc コメントは「窓ごとのライブ値はここから配ってはならない」と定めており、その禁止を型の依存で担保している。サイドバー 4 値も同じ扱いへ移るため、この型が SidebarDisplayPreference を持たなくなる形を目指す(持たなければ配れない、という構造で担保する)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌃⌘T・不可視ファイル・変更ファイルのみ・並び順の変更が、アクティブウィンドウのサイドバーだけに反映される
- [ ] #2 View メニューのチェック状態がアクティブウィンドウの値を反映する
- [ ] #3 サイドバーヘッダーのアイコンボタンからの操作も同じ窓だけに閉じる
- [ ] #4 CLI の --hidden-files / --no-hidden-files が、その起動で開くウィンドウに適用される
- [ ] #5 GlobalDisplayBroadcaster が SidebarDisplayPreference を保持しない
<!-- AC:END -->
