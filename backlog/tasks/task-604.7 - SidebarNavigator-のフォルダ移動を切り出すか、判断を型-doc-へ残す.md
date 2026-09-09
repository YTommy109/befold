---
id: TASK-604.7
title: SidebarNavigator のフォルダ移動を切り出すか、判断を型 doc へ残す
status: To Do
assignee: []
created_date: '2026-09-09 00:03'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: low
ordinal: 883000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/SidebarNavigator` グループは 398 行（本体 315 + `+FolderNavigation` 83）。

## 状況

**すでに 8 個の協力型へ責務が出ている**（`SidebarTreePresenter` 218 / `SidebarListingCoordinator` 208 / `SidebarLayoutTransition` 121 / `SidebarPostSwitchSync` 65 / `SidebarHistoryController` / `SidebarGitStatusCoordinator` / `SidebarBaseDirectoryResolver` / `SidebarSelectionMemory`）。本体 315 行の内訳は doc 108 行・空行 33 行・実コード 157 行で、**そのうち 20 本が 1 行の委譲**。

## 切り出せるもの（約 −60 行、398 → 約 338）

呼び出し元の実測:

| メソッド | 型外の呼び出し元 |
|---|---|
| `select(_:presentingWith:)` (`+FolderNavigation.swift:61`) | **0** |
| `updateRootDirectory(with:)` (同 `:73`) | **0**（純粋なパス比較） |
| `navigateToFolder(_:)` (同 `:15`) | 本番 1 箇所（`ViewerWindowController+FileNavigation.swift:26`） |
| `moveCurrentDirectory(to:)` (同 `:49`) | **4 箇所。doc が「currentDirectory を書き換える唯一の経路（TASK-465）」と宣言しており移せない** |

上 3 つ（約 62 行）を `SidebarFolderNavigation`（`SidebarPostSwitchSync.apply(on:...)` と同じ「ナビゲータを引数で受ける静的ヘルパー」の形）へ出せる。

## ただし「返済」と呼んでよいか判断が要る（確度 中）

- `navigateToFolder` は**本体の stored property を 6/9 個参照する**。切り出しても行数が移るだけで**結合は下がらない**
- protocol 準拠 0・注入クロージャ 3（上限ちょうど、超過していない）。関心の同居を測る指標が飽和していない
- 本体に残る 20 本の委譲は削れない。`SidebarNavigator` は**協力型どうしが呼び戻すハブ**（`SidebarLayoutTransition.swift:64` → `navigator.moveCurrentDirectory` 等）で、委譲を消すと協力型が総当たりで依存し合う
- `awaitSettled` と 3 本の `pending*Task`（`:135-184`、50 行中 40 行が doc）はテストの待ち合わせ窓という別の関心だが、3 つの private 協力型を跨ぐので出せない（出すと `tree` を private にした理由 `:31-35` と衝突）

## 移動できないコード: 0 行

@objc 0・protocol 準拠 0・NSResponder ではない。`ViewerWindowController` の例外理由は当てはまらない。

## 着手時に決めること

行数だけを移す切り出しを行うか、行わずに**上の判断を型 doc へ残して閉じる**か。後者を選ぶ場合、400 行を超えた時点で恒久例外へ登録することになるので、その理由文案まで用意する（TASK-604 の Notes に文案あり）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 切り出すか残すかの判断が理由つきで記録され、選んだ側が実施されている
- [ ] #2 残す判断の場合、ハブ構造と moveCurrentDirectory の単一経路の理由が SidebarNavigator の型 doc にある
<!-- AC:END -->
