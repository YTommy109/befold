---
id: TASK-921
title: サイドバーの一覧で NSTableView の再入の警告が出る原因を特定する
status: To Do
assignee: []
created_date: '2026-11-07T12:47:00Z'
labels:
  - sidebar
  - appkit
dependencies: []
priority: medium
type: bug
ordinal: 887000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-11-07 の実機確認（スタック #769 の最上層を Xcode 27.2 の Debug でビルドし、設定を分離して起動）で、アプリのログに次の警告が 1 回だけ出た。`WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.` AppKit は将来これを assert に変えると書いているので、放置すると将来の macOS でクラッシュになりうる。サイドバーの一覧は SwiftUI の `List` で、背後の `NSTableView` を `SidebarTableFocuser` が first responder にし、選択の変更で `fileListDidSelectFile` から窓の切り替えや空タブの置き換えが走る。どの操作で出たかは記録できていない。同じ回では空タブ・サイドバー・ドロップ・Quick Open・Reload など 8 項目を操作していた。2 回目の実機確認（サブフォルダへの移動の 1 手順だけ）では出なかった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 警告が出る操作手順を特定し、Notes に記録している（特定できなければ、試した手順と結果を記録している）
- [ ] #2 原因が befold のコードにあれば直し、同じ手順で警告が出ないことを確かめている
- [ ] #3 原因が AppKit や SwiftUI の側にあれば、その根拠と回避の要否を記録している
<!-- AC:END -->
