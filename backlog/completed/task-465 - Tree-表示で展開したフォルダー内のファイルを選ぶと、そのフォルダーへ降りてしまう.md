---
id: TASK-465
title: Tree 表示で展開したフォルダー内のファイルを選ぶと、そのフォルダーへ降りてしまう
status: Done
assignee:
  - '@claude'
created_date: '2026-08-12 13:15'
updated_date: '2026-08-12 15:52'
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
- [x] #1 Tree 表示で展開したサブフォルダー内のファイルを選択しても currentDirectory が変わらない（マウスクリック・j/k・矢印・return のすべてで）
- [x] #2 Tree 表示でファイルを選択しても展開状態（expanded な行構成）が維持される
- [x] #3 drillDown 表示での既存挙動（Quick Open 等、一覧外のファイルへ切り替えたときにフォルダーが追従する）が回帰していない
- [x] #4 currentDirectory を書き換える経路が一本化されている（syncAfterSwitch と navigateToFolder の二重経路の解消可否を検討し、結論を Implementation Notes に残す）
- [x] #5 tree 展開下の子ファイル選択後に currentDirectory が保たれることを検証するユニットテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. syncAfterSwitch の判定を『親ディレクトリ比較』から『いま一覧にその行があるか』へ変える(tree/drillDown で分岐しない)
2. currentDirectory を書き換える経路を moveCurrentDirectory(to:) 1 本に畳み、navigateToFolder もそれを通す
3. SidebarNavigatorSyncAfterSwitchTests を追加(tree 展開下の子選択で currentDirectory・展開が保たれる / 一覧外のファイルでは追従する)
4. swift test と swiftlint ベースライン差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因と修正

syncAfterSwitch が『切替先の親ディレクトリ != currentDirectory ならフォルダーを動かす』
と判定していた。tree では展開したサブフォルダーの子行が同じ一覧に並ぶため、この条件が
常に真になりフォルダー移動が誤発火していた。判定を『いま出ている一覧からその行を選べるか』
(SidebarNavigator.isReachableInCurrentListing)へ変え、レイアウトで分岐しない形にした。
起動直後の一覧未到着に備え、親ディレクトリ一致も同じ扱いにしている。

## AC #4 の結論(currentDirectory 書き換え経路の一本化)

SidebarNavigator+FolderNavigation に moveCurrentDirectory(to:) を新設し、
『移動前の選択の記憶 / rootDirectory 更新 / 展開の破棄』の後始末をそこへ畳んだ。
navigateToFolder・syncAfterSwitch に加え、同じ生の代入をしていた
ViewerWindowController+FileNavigation.moveSidebarToDirectoryIfNeeded(リネーム追随)も
この経路へ通した。SidebarHistoryController の代入だけは残している——履歴の適用は
『記録済みの状態へ戻す』操作で、記憶の上書きや展開の破棄という後始末が意味を持たない
(むしろ復元を壊す)ため。判断: 一本化するのは『新しい場所へ動かす』経路のみ。

## 検証

- swift test: 1461 tests / 229 suites 全 pass
- 追加テストは修正前に失敗することを確認済み(currentDirectory が .../sub へ移動、
  selection が fileA.mmd のまま — 実測ログあり)
- swiftlint: 55 件(全体)、変更した 3 ファイルの指摘は 0 件
- AC #1 の入力手段の網羅は、クリック・j/k・矢印・return がすべて
  FileListView.onSelect -> ViewerWindowAssembler:100 -> switchFile の 1 経路に
  合流していることをコードで確認(入口が 1 つなので syncAfterSwitch のテストで足りる)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
syncAfterSwitch の判定を『親ディレクトリ比較』から『いま出ている一覧から選べるか』へ変え、tree 展開下の子ファイル選択でフォルダー移動が誤発火するのを止めた。あわせて currentDirectory を書き換える経路を moveCurrentDirectory(to:) 1 本へ畳んだ(履歴適用のみ意図的に除外、理由は Notes)。修正前に失敗することを確認した SidebarNavigatorSyncAfterSwitchTests を追加し、swift test 1461 件全 pass・変更ファイルの swiftlint 指摘 0 件で検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
