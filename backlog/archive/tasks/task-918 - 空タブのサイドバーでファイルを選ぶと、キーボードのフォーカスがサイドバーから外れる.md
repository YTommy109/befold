---
id: TASK-918
title: 空タブのサイドバーでファイルを選ぶと、キーボードのフォーカスがサイドバーから外れる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T12:09:00Z'
labels:
  - sidebar
  - tabs
  - keyboard
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController+Sidebar.swift
  - BefoldApp/befold/Viewer/FileListView.swift
priority: medium
type: bug
ordinal: 884000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。矢印キーや j/k で空タブのサイドバーを操作してファイルを選ぶと、文書タブへ置き換わった後にキー操作が続かない。文書タブでは TASK-581 で「サイドバー由来のオープンはフォーカスをサイドバーに残す」としており、続けて次のファイルへ移れる。

裏付け（コード参照・実機未確認）: `FileListView` の `tableFocuser.focus()` は閉じる空タブの `FileListModel` に対して走る。`BlankTabWindowController.fileListDidSelectFile` から新しい `ViewerWindowController` の表へフォーカスを渡す経路は無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 空タブのサイドバーをキーボードで操作して開いた文書タブで、サイドバーの表がフォーカスを持つ
- [x] #2 続けて矢印キーを押すと次の行へ移り、そのファイルが表示される
- [x] #3 Quick Open など本文へフォーカスを置く経路の動作は変わらない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 置き換えた文書タブの focusSidebar を呼ぶ。focusSidebar はサイドバーが閉じていれば何もしない形にし、メニュー（⌘←）と空タブからの置き換えで共有する（判定は表示前でも正しい resolvedSidebarCollapsed）。
code-review high: 同じグループの既存タブを再利用するとき、閉じたサイドバーへフォーカスを移す不具合を検出して直した（判定を外すと reusedTabWithCollapsedSidebarKeepsFocus が落ちる）。複数行の guard も直した。遅れて成立するフォーカスは文書タブのサイドバー選択と同じ形なので、空タブだけ変えずに残した。閉じた空タブの表へ届く余分な要求は実害が無いので残した。
ViewerWindowController グループは上限 939 に収めるため、ツールバーの説明を 1 行に畳んだ。
実測: 修正を外すと replacedDocumentSidebarTakesFocus が落ちる。swift test 1996 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。矢印キーでの操作（AC #2）は実機確認でまとめて行う。Quick Open など本文へフォーカスを置く経路（AC #3）は変更していない。

実機確認（2026-11-07、同上）: 空タブのサイドバーを矢印キーで操作して文書タブへ置き換えた後、続けて矢印キーで次の行へ移り、そのファイルが表示された。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
空タブのサイドバーから開いた文書タブへフォーカスを渡し、キー操作が続くようにした。focusSidebar はサイドバーが閉じていれば何もしない形にし、⌘← と共有する。
<!-- SECTION:FINAL_SUMMARY:END -->
