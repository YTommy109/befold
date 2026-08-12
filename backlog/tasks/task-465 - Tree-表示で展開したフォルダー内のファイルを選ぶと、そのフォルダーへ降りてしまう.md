---
id: TASK-465
title: Tree 表示で展開したフォルダー内のファイルを選ぶと、そのフォルダーへ降りてしまう
status: To Do
assignee: []
created_date: '2026-08-12 13:15'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 688000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの Tree 表示でフォルダーを展開し、その中のファイルを選択（マウスクリック／j,k・矢印・return いずれでも）すると、意図せず表示中のフォルダーがその展開先サブフォルダーへ移動してしまう。

原因: ViewerWindowController+FileNavigation.swift:36-46 の switchFile が成功時に SidebarNavigator.syncAfterSwitch(to:) を呼び、SidebarNavigator.swift:299-308 が『選択ファイルの親ディレクトリ != currentDirectory なら currentDirectory を書き換えて refreshFileList()』という判定を layoutMode を見ずに行っている。drillDown では一覧のファイルは必ず currentDirectory 直下なので条件は常に偽だが、tree では展開したサブフォルダーの子行が同じ一覧に並ぶため条件が必ず真になり、currentDirectory がサブフォルダーへ差し替わる（= フォルダー移動が発火）。副作用として再列挙でツリーの行構成（展開のルート）も差し替わる。

非対称性: 明示的なフォルダー移動 navigateToFolder は SidebarNavigator+FolderNavigation.swift:29 で discardExpansion() を通す前提だが、syncAfterSwitch はその経路を通らず currentDirectory を直接書き換えている。設計として『currentDirectory を動かす経路』が二重になっている点の単純化（一本化）を実装前に検討すること。

既存テスト: syncAfterSwitch を直接検証するテストは無い（grep ヒット 0）。tree の選択・キー操作のテストは FileListView 単体（onSelect スタブ）で switchFile 以降を通していない。SidebarNavigatorIntegrationTests.swift:27 は symlink 祖先ケースのみ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tree 表示で展開したサブフォルダー内のファイルを選択しても currentDirectory が変わらない（マウスクリック・j/k・矢印・return のすべてで）
- [ ] #2 Tree 表示でファイルを選択しても展開状態（expanded な行構成）が維持される
- [ ] #3 drillDown 表示での既存挙動（Quick Open 等、一覧外のファイルへ切り替えたときにフォルダーが追従する）が回帰していない
- [ ] #4 currentDirectory を書き換える経路が一本化されている（syncAfterSwitch と navigateToFolder の二重経路の解消可否を検討し、結論を Implementation Notes に残す）
- [ ] #5 tree 展開下の子ファイル選択後に currentDirectory が保たれることを検証するユニットテストが追加されている
<!-- AC:END -->
