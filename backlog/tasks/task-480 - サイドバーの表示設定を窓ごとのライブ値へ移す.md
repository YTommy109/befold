---
id: TASK-480
title: サイドバーの表示設定を窓ごとのライブ値へ移す
status: To Do
assignee: []
created_date: '2026-08-14 08:00'
labels: []
dependencies: []
documentation:
  - docs/adr/0002-presentation-state-and-capabilities.md
priority: high
type: task
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの表示設定 4 値(表示形式 layoutMode / 不可視ファイル showHiddenFiles / 変更ファイルのみ showChangedFilesOnly / 並び順 sortOrder)は現在 app-global の SidebarDisplayPreference 1 インスタンスを全ウィンドウで共有しており、⌃⌘T などの操作がアクティブでないウィンドウのサイドバーまで切り替えてしまう。これはバグではなく現在の設計どおりの挙動だが(GlobalDisplayBroadcaster の doc コメント参照)、ユーザーの期待は「操作したウィンドウだけが変わる」であり、粒度の選択自体を見直す。

窓ごとの表示状態(ViewerDisplayMode / ZoomStore)は ADR 0002 で既に窓側の責務と定めており、サイドバー表示 4 値もそちら側へ寄せる。永続化は app-global キーを「新規ウィンドウの初期値」として残す形にし、既存ユーザーの設定が失われないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバー表示 4 値の変更が、操作したウィンドウのサイドバーだけに反映される
- [ ] #2 新規ウィンドウは、最後に使われた値を初期値として開く
- [ ] #3 既存ユーザーの UserDefaults 保存値が移行後も初期値として引き継がれる
- [ ] #4 ADR 0002 に、サイドバー表示 4 値の粒度と永続化の位置づけが記載されている
<!-- AC:END -->
