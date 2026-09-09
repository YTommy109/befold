---
id: TASK-604.7
title: SidebarNavigator のフォルダ移動を切り出すか、判断を型 doc へ残す
status: Done
assignee: []
created_date: '2026-09-09 00:03'
updated_date: '2026-09-09 01:17'
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
- [x] #1 切り出すか残すかの判断が理由つきで記録され、選んだ側が実施されている
- [x] #2 残す判断の場合、ハブ構造と moveCurrentDirectory の単一経路の理由が SidebarNavigator の型 doc にある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 判断: 切り出さない

`SidebarFolderNavigation` への切り出しは行わず、判断を型 doc へ残して恒久例外へ登録した。

### 実測で確かめたこと

- **呼び出し元**（`rg` 実測）: `navigateToFolder` は型外 1 箇所
  （`ViewerWindowController+FileNavigation.swift:26`）、`updateRootDirectory` と
  `select(_:presentingWith:)` は 0、`moveCurrentDirectory` は型外 4 箇所
  （`SidebarLayoutTransition` ×2 / `SidebarPostSwitchSync` / `ViewerWindowController`）。
- **決め手は協力型の可視性**: `tree` / `listing` / `layoutTransition` / `baseDirectory` /
  `gitStatus` はいずれも意図して `private`（`SidebarNavigator.swift` の各 doc。
  TASK-319 / TASK-442.5）。`navigateToFolder` を別型へ移しても
  `performListing` / `applyRows` / `discardExpansion` というこの型の薄い委譲を通るため、
  **行数が移るだけで結合は下がらない**（起票時の「確度 中」はここで「切り出さない」に確定）。
- `+FolderNavigation.swift` の doc 自身が「本体から分けているのは file_length を
  超えないため」と書いている。その上に型を 1 つ足すのは
  `scripts/check-type-group-size.sh` のヘッダが塞ごうとしている逃げ道そのもの。
- `moveCurrentDirectory` は `currentDirectory` を書き換える唯一の経路（TASK-465）で
  型外 4 箇所から呼ばれるため動かせず、切り出すと `navigateToFolder` と分断される。
- 関心の同居を測る指標は飽和していない: protocol 準拠 0 / 注入クロージャ 3（上限ちょうど）/
  `@objc` 0 / NSResponder ではない。**行数だけが 400 に近い**状態。

### 実施したこと

- `SidebarNavigator` の型 doc に「これ以上分割しない」節を追加（AC #2）。
  ハブ構造・`moveCurrentDirectory` の単一経路・`awaitSettled` を出せない理由を含む。
- `scripts/type-group-exceptions.txt` へ登録（上限 425）。
  **doc を書いたぶんで 398 → 425 になった**——TASK-547 が踏んだ
  「判断を doc に残そうとしたら閾値に引っかかって書けない」形をここでも踏んだので、
  判断の記録と例外登録を同じコミットで行っている。

### 検証

- `scripts/check-type-group-size.sh --check`: 「型グループの行数は閾値以内です」
- `swift build` エラー 0、`swift test` 1945 tests 全パス（変更はコメントと txt のみ）
- swiftlint: main とのベースライン差分ゼロ（`SidebarNavigator.swift` 単体は 342 行で
  `file_length` にも掛からない）
<!-- SECTION:NOTES:END -->
