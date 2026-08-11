---
id: TASK-442.3
title: ツリー展開と行の組み立てを SidebarTreePresenter へ切り出す
status: To Do
assignee: []
created_date: '2026-08-11 07:35'
labels: []
dependencies:
  - TASK-442.1
parent_task_id: TASK-442
ordinal: 675000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator+Expansion.swift (87 行) 全体と、SidebarNavigator の expansion / childrenLister を新規の @MainActor final class SidebarTreePresenter へ移す。展開状態 (SidebarExpansion) / 行の組み立て (applyRows) / 子リストの取得 (childrenLister) は別々の関心が同居しているのではなく、1 つの出力 (FileListModel.entries) を作るための状態・材料・生成器であり、SidebarExpansion.swift:14-19 の doc が「展開状態と行生成を切り離すな」と指示している内容を型境界として実体化する。

責務分離であって行数回避でないことの実証として、次の 2 つを同じタスクで行う。

1. presenter が rootRows を stored property として保持し、rebuildRows() の fileListModel.entries.filter { $0.depth == 0 } による逆算 (+Expansion.swift:47) を消す。
2. SidebarExpansion.ExpansionToken に URL を持たせ、reloadExpandedChildren が folderEntryURL でフォルダ URL を引き直している (+Expansion.swift:73) のをやめる。beginExpanding の呼び出し元 expandFolder(_:at:) は URL を持っているため、券に載せれば引き当て自体が不要になる。

presenter は注入しない。childrenLister だけを SidebarNavigator.init の引数として受け、内部で生成して渡す (SidebarExpansion の非注入方針 = TASK-319 と同型の事故防止を維持する)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SidebarNavigator+Expansion.swift が無くなり、内容が SidebarTreePresenter へ移っている
- [ ] #2 presenter が rootRows を保持し、depth == 0 のフィルタによる逆算が無い
- [ ] #3 ExpansionToken が URL を持ち、reloadExpandedChildren がフォルダ URL の引き当てを行わない
- [ ] #4 presenter は SidebarNavigator.init の引数ではなく内部で生成される (ウィンドウごとに 1 つが構造で守られる)
- [ ] #5 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
