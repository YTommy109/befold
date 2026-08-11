---
id: TASK-442.1
title: サイドバーの行生成を 1 箇所へ一本化する
status: To Do
assignee: []
created_date: '2026-08-11 07:34'
labels: []
dependencies: []
parent_task_id: TASK-442
ordinal: 673000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarExpansion.swift:15 の doc は「行の生成は SidebarNavigator の 1 箇所だけが行う」と書いているが、実態は 2 箇所。DirectoryLister.buildEntries (DirectoryLister.swift:96) が「展開集合が空」の縮退形で SidebarRowBuilder.rows を通して行を組み、それを SidebarNavigator+Expansion.applyRows (:25-27) が kind == .parentNavigation で分解し直して再度 SidebarRowBuilder.rows へ通している。1 回の列挙で行の組み立てが 2 回走っている。

TASK-442 の分割で行の組み立てを独立型へ移すが、その型の doc に「1 箇所」と書いた時点で嘘になるため、先にここを片付ける。

方針の候補: DirectoryLister が組み立て済みの [FileListEntry] を返すのをやめ、(parentEntry, rootChildren) を返す形にして、組み立ては呼び出し側の 1 箇所だけにする。appendingOpenFile / listEntriesAsync / childEntriesAsync のシグネチャと、それらを直接使っているテストへの波及を調べた上で決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーの行の組み立て (SidebarRowBuilder.rows の呼び出し) がプロダクトコードで 1 箇所だけになっている
- [ ] #2 その事実をソース走査で検証するテストがある (ViewerBridgeTests のソース突き合わせと同じ流儀)。呼び出しを 2 箇所目へ増やすと落ちる
- [ ] #3 SidebarExpansion.swift の doc の記述が実態と一致している
- [ ] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
