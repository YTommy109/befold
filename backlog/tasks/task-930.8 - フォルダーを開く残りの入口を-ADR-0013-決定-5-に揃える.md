---
id: TASK-930.8
title: フォルダーを開く残りの入口を ADR 0013 決定 5 に揃える
status: To Do
assignee: []
created_date: '2026-11-25T13:14:02Z'
labels: []
dependencies: []
parent_task_id: TASK-930
priority: low
type: bug
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘(2026-11-25、いずれも nit)。原因は同じで、TASK-930.4 でディレクトリを一覧の窓で開くようにしたとき、文書の開き方にある規則が一部移っていない。(1) DocumentOpener.openViewer のディレクトリ分岐は disposition・sourceWindow・placement・prefersExistingWindow を見ず、常に新しい窓を作る。befold <dir> を 2 回実行すると同じ一覧の窓が 2 つでき、手前の空タブから Open Recent でフォルダーを選んでも空タブは置き換わらない(openViewer(for:) の doc コメントと食い違う)。(2) ViewerDisplayOptionsApplier.folderSeed / apply(_:toFolderWindow:) は並び順・不可視ファイル・開閉だけを当て、--compare-to を一覧の窓の comparisonTarget に当てない。--line / --source などは何も言わずに捨てる。(3) サイドバーのフォルダー行のコンテキストメニュー「新しいタブ/ウィンドウで開く」は、いまもフォルダー内の最初のファイル(DirectoryLister.firstSupportedFile)を開く(SidebarContextMenu.openElsewhereButton)。コード上の該当は確認済み、実機での再現は未実施。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同じディレクトリを再度開くと既存の一覧の窓を前面に出し、空タブが起点なら置き換える(文書と同じ再利用規則)
- [ ] #2 --compare-to をディレクトリの窓に当て、ディレクトリだけを開くときに意味の無いオプションは警告するか拒否する
- [ ] #3 コンテキストメニューの新しいタブ/ウィンドウで開くは、フォルダーの一覧を出す
- [ ] #4 各経路をテストで確かめる
<!-- AC:END -->
