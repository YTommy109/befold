---
id: TASK-480
title: サイドバーの表示設定を窓ごとのライブ値へ移す
status: Done
assignee: []
created_date: '2026-08-14 08:00'
updated_date: '2026-08-14 11:46'
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
- [x] #1 サイドバー表示 4 値の変更が、操作したウィンドウのサイドバーだけに反映される
- [x] #2 新規ウィンドウは、最後に使われた値を初期値として開く
- [x] #3 既存ユーザーの UserDefaults 保存値が移行後も初期値として引き継がれる
- [x] #4 ADR 0002 に、サイドバー表示 4 値の粒度と永続化の位置づけが記載されている
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの表示設定 4 値(表示形式 / 不可視ファイル / 変更ファイルのみ / 並び順)を app-global 共有から窓ごとのライブ値へ移した。ADR 0002 の状態分類を 2 分類から 3 分類へ引き直して「窓の状態」を新設し(480.1)、真実の源を窓ごとの FileListModel 1 本へ畳んで既定値ストアを初期値供給＋書き戻し専用へ縮退させ(480.2)、操作経路をアクティブウィンドウ 1 つへ向けた(480.3)。UserDefaults の 4 キーは名前・型・値の domain とも不変で新規ウィンドウの初期値として引き継がれるため、移行処理は不要。検証: swift test 1511 tests passed、swiftlint は main とのベースライン差分ゼロ、check-type-group-size.sh / check-doc-symbols.sh / markdownlint-cli2 いずれも通過。挙動変更 3 点(操作した窓だけが変わる / CLI --hidden-files が既定値を書き換えない / 窓が無いとき View メニューの該当 3 項目が無効)は 480.3 の Notes に記録。
<!-- SECTION:FINAL_SUMMARY:END -->
