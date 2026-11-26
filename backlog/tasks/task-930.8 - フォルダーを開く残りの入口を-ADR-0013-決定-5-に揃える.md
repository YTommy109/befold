---
id: TASK-930.8
title: フォルダーを開く残りの入口を ADR 0013 決定 5 に揃える
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-25T13:14:02Z'
updated_date: '2026-11-26T01:35:32Z'
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
- [ ] #1 同じディレクトリを手前のタブ扱い(既定)でもう一度開くと、既存の一覧の窓を前面に出す(新しい窓を作らない)。--new-window なら新しい窓
- [ ] #2 --compare-to をディレクトリの窓の比較基準に当てる。文書にしか意味の無いオプションをディレクトリだけに付けたら標準エラーへ警告し、窓は開く
- [ ] #3 サイドバーのフォルダー行で「新しいタブ/ウィンドウで開く」(メニュー・⌘クリック・⌘Return)を選ぶと、新しいタブ/窓にそのフォルダーの一覧を出す
- [ ] #4 各経路をテストで確かめ、修正を戻すと落ちることを確かめる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
到達性の調査(2026-11-26): ディレクトリが届く入口は CLI(openPaths)と Finder/Dock(openSequentially)だけで、どちらも起点の窓は無い。開くパネルは canChooseDirectories が既定の false、openInTabs は allowsDirectories: false、Open Recent・ブックマークはファイルのみ。手前の空タブを起点にディレクトリが来る経路は無いので、AC#1 の「空タブを置き換える」は外す。
方針(ユーザー決定 2026-11-26): (a) フォルダー行の「新しいタブ/ウィンドウで開く」はフォルダーの一覧を開く。⌘クリック・⌘Return もフォルダー行で同じく効かせる。(b) 文書にしか意味の無い CLI オプションをディレクトリだけに付けたら、標準エラーへ警告して続ける(終了コード 0)。(c) --compare-to はディレクトリの窓にも当てる。
<!-- SECTION:NOTES:END -->
