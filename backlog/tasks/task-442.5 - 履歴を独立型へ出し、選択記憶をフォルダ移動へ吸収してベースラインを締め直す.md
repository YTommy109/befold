---
id: TASK-442.5
title: 履歴を独立型へ出し、選択記憶をフォルダ移動へ吸収してベースラインを締め直す
status: To Do
assignee: []
created_date: '2026-08-11 07:36'
labels: []
dependencies:
  - TASK-442.4
parent_task_id: TASK-442
ordinal: 677000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-442 の仕上げ。ここまでで型グループは 420〜430 行の見込みで、AC の 400 行にはまだ届かない。

1. SidebarNavigator+History.swift (70 行) を独立型へ出す。この extension は 4 本の中で唯一 doc が「行数のため」ではなく「一覧・git 状態の取得とは独立した関心事」と書いており (+History.swift:5)、触る本体 stored は history (専有) / fileListModel / host の 3 個だけ。着手判断のライン: applyHistoryEntry が refreshFileList(applyCustomSelection:) を呼び返すため逆方向の参照が 1 本要る。これがクロージャ 1 個または weak 参照 1 本で済むなら実施し、3 本以上必要になるなら実施せず理由を記録する。
2. SidebarNavigator+SelectionMemory.swift (23 行) を +FolderNavigation.swift へ吸収する。メソッド 2 個・stored 1 個で、呼び出し元は navigateToFolder の 2 箇所のみ。責務が分かれている証拠にならないファイル分割であり、同一ファイルにすれば selectionMemory を private へ落とせる。
3. e94161d で緩んだ隠蔽の始末。folderEntryURL(forKey:) は TASK-442.2 で FileListModel へ移って本体から消えている。host は +FolderNavigation / +History が読むため Swift の private (ファイルスコープ) では戻せない。private(set) のまま残す理由を doc コメントに明記する。
4. scripts/type-group-baseline.txt から SidebarNavigator のエントリを消す (--update-baseline)。新型が閾値未満であることも確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループの合算行数が 400 行以下になっている (scripts/check-type-group-size.sh --check が通る)
- [ ] #2 scripts/type-group-baseline.txt から SidebarNavigator のエントリが消えている
- [ ] #3 SidebarNavigator+SelectionMemory.swift が無くなり、selectionMemory が private になっている
- [ ] #4 履歴を独立型へ出したか、出さなかった場合はその理由 (逆方向の参照が何本必要だったか) が Implementation Notes に記録されている
- [ ] #5 host が private(set) のまま残る理由が doc コメントに明記されている
- [ ] #6 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
