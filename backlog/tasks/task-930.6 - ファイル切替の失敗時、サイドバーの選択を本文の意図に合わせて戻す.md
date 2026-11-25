---
id: TASK-930.6
title: ファイル切替の失敗時、サイドバーの選択を本文の意図に合わせて戻す
status: To Do
assignee: []
created_date: '2026-11-25T13:13:58Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25)。ViewerWindowController.switchFile の .failed 分岐は sidebar.restoreSelection(to: oldURL) で開いている文書の行へ選択を戻す。提示を選択から導いていた頃は正しかったが、ADR 0013 以降はフォルダー一覧を出している間(意図 .folder(X))も文書の行が強調される。TASK-930.3 で SidebarListingCoordinator から取り除いたのと同じ不整合(提示していない行が光り、表示形式の切り替えでカレントが文書の親へ移る)。再現手順(未実測): フォルダー X の一覧を出す → Finder で X/a.md を削除 → 取り直し前に本文の一覧の a.md を押す → 切替が失敗し、本文は X の一覧のまま文書の行が強調される。コード上の該当は確認済み、実機・テストでの再現は未実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダー一覧の表示中にファイル切替が失敗したとき、選択は意図に合う値(表示中フォルダー自身の一覧なら nil、フォルダー行ならその URL)へ戻り、文書の行は強調されない
- [ ] #2 その状態で表示形式を切り替えても currentDirectory が文書の親へ移らないことをテストで確かめる
- [ ] #3 修正を戻すとテストが落ちることを確かめる
<!-- AC:END -->
