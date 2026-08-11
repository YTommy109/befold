---
id: TASK-443
title: FileListModel / FileListView（型グループ 459 行 / 437 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-11 05:06'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 109400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/Viewer/ のサイドバー系 2 グループが閾値 400 を超えている。scripts/check-type-group-size.sh の実測値で scripts/type-group-baseline.txt にも凍結されている。

- FileListModel 459 行（本体 378 / +Snapshot 55 / +TreeRows 26）
- FileListView 437 行（本体 326 / +Keyboard 111）

どちらもファイル単位では file_length の warning 400 を下回っており、TASK-428 の起票時のファイル単位リスト（7 件）には現れていなかった。合算で初めて顕在化したグループ。超過幅は他の返済対象（ViewerRenderer 1300 / ViewerWindowController 1255 / SidebarNavigator 611）より小さいため priority は low。

2 つを 1 タスクにまとめているのは、同じサイドバーの表示経路にあり、モデル側とビュー側で関心の置き場所を同時に決めたほうが筋が良いため。分割の途中でどちらか片方だけが閾値以下になる状態は許容するが、タスクの完了は両方が閾値以下になった時点とする。

分割は extension を増やす形では効かない（合算値が減らない）。独立型へ関心を出すこと。着手前に responsibility-reviewer サブエージェントを回して切り口を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FileListModel の型グループ合算行数が 400 行以下になる
- [ ] #2 FileListView の型グループ合算行数が 400 行以下になる
- [ ] #3 ベースライン scripts/type-group-baseline.txt から両グループのエントリが消える
- [ ] #4 分割は extension の追加ではなく独立型への切り出しで行われている
- [ ] #5 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [ ] #6 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->
