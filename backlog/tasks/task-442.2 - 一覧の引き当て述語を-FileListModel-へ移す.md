---
id: TASK-442.2
title: 一覧の引き当て述語を FileListModel へ移す
status: To Do
assignee: []
created_date: '2026-08-11 07:34'
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
- [ ] #1 folderEntryURL(forKey:) / matchingEntryURL(for:) が FileListModel 側へ移り、SidebarNavigator 型グループから消えている
- [ ] #2 呼び出し元 (+History / +FolderNavigation / +Expansion / 本体 refreshFileList / syncAfterSwitch) がすべて FileListModel 経由へ書き換わっている
- [ ] #3 移した述語のユニットテストが FileListModel 側にある
- [ ] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
