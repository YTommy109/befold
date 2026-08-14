---
id: TASK-480.3
title: サイドバー表示の操作経路をアクティブウィンドウのみへ向ける
status: To Do
assignee: []
created_date: '2026-08-14 08:02'
updated_date: '2026-08-14 11:02'
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
- [ ] #4 CLI の --hidden-files / --no-hidden-files が、その起動で開くウィンドウにだけ適用され、UserDefaults の既定値を書き換えない(--sort と同じ「その起動限りの上書き」に揃える)
- [ ] #5 GlobalDisplayBroadcaster が SidebarDisplayDefaults(旧 SidebarDisplayPreference)を保持しない
- [ ] #6 AppQuickOpenEnvironment.includingHiddenFiles が、Quick Open を開いたウィンドウの値を読む
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-480.2 の /review-design で 2 点をスコープへ追加した(2026-08-14、ユーザー承認済み)。
1. AppQuickOpenEnvironment.swift:39 の includingHiddenFiles が app-global 値を読んでおり、当初どの AC にも入っていなかった。窓ごと化後に唯一のグローバル読み手として残るため AC#6 として追加。
2. CLI --hidden-files は現在 GlobalDisplayBroadcaster.setHiddenFiles で UserDefaults を書き換えて全窓へ配る(GlobalDisplayBroadcaster.swift:69-80)。一方 --sort は「その起動限りの上書きで共有設定を書き換えない」(ViewerDisplayOptionsApplier.swift:28-33)。ADR 0002 の CLI 規則は後者なので --sort へ揃える(挙動変更)。CLIOpenOptions.swift:36 の doc コメント「これだけはアプリ全体設定のため対象を要さない」も書き換え対象。
<!-- SECTION:NOTES:END -->
