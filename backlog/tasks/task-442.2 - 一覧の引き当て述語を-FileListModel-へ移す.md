---
id: TASK-442.2
title: 一覧の引き当て述語を FileListModel へ移す
status: Done
assignee: []
created_date: '2026-08-11 07:34'
updated_date: '2026-08-11 08:16'
labels: []
dependencies:
  - TASK-442.1
parent_task_id: TASK-442
ordinal: 674000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator.folderEntryURL(forKey:) (SidebarNavigator.swift:332) と matchingEntryURL(for:) (:340) は、どちらも FileListModel.entries に対する検索述語で、SidebarNavigator 固有の関心ではない。現在は同一型の別ファイル extension 3 本 (+History :49 / +FolderNavigation :34 / +Expansion :73) から参照されるため internal に上げざるを得ず、TASK-442 の e94161d で folderEntryURL の private が外れた原因にもなっている。

FileListModel 側 (必要なら FileListModel+Lookup.swift) へ移し、fileListModel.folderEntryURL(forKey:) / fileListModel.matchingEntryURL(for:) にする。SidebarNavigator からは両メソッドが消える。

依存: TASK-442.2 で切り出す型からも同じ述語を引くため、442.2 より前か同時に行うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 folderEntryURL(forKey:) / matchingEntryURL(for:) が FileListModel 側へ移り、SidebarNavigator 型グループから消えている
- [x] #2 呼び出し元 (+History / +FolderNavigation / +Expansion / 本体 refreshFileList / syncAfterSwitch) がすべて FileListModel 経由へ書き換わっている
- [x] #3 移した述語のユニットテストが FileListModel 側にある
- [x] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FileListModel+Lookup.swift へ folderEntryURL(forKey:) / matchingEntryURL(for:) を移設。線形走査だった 2 述語は既存の FileListEntryIndex（entry(forPathKey:) を追加）経由の O(1) 引き当てへ変更した（索引は private のため FileListModel.entry(forPathKey:) を経由）。呼び出し元 4 ファイル 5 箇所を fileListModel. 経由へ書き換え、SidebarNavigator 型グループから両述語が消えた。検証: swift test 1405 tests passed / swiftlint は SidebarNavigator+History.swift:39 の既存 opening_brace 1 件のみで新規なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
一覧の引き当て述語 2 本を FileListModel+Lookup.swift へ移し、索引経由の O(1) 引き当てにした。FileListModelLookupTests 4 件を追加し、swift test 1405 件通過・swiftlint 新規ゼロを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
