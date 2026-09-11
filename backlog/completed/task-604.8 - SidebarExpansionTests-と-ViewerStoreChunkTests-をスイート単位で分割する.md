---
id: TASK-604.8
title: SidebarExpansionTests と ViewerStoreChunkTests をスイート単位で分割する
status: Done
assignee: []
created_date: '2026-09-09 00:03'
updated_date: '2026-09-09 01:25'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: medium
ordinal: 884000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
どちらも単一ファイルで閾値に張り付いており、`// MARK:` で既に関心が割れている。分割方式は TASK-431 が決めた**別名の独立 @Suite**（`Foo+Bar.swift` の extension は合算されるため返済にならない）。

## `SidebarExpansionTests.swift`（399 行、残り 1 行。@Test 23）

対象は `SidebarExpansion.swift`（236 行）1 型。最も独立しているのは末尾ブロック `:352-398`（48 行 4 テスト、TASK-481 のレイアウト切替スナップショット root）で、`snapshotRoot` / `coverage` という別 API・別タスク。展開の世代ガードとはデータも関心も交わらない。次点は TASK-404 の列挙失敗ブロック（`:50-159`、110 行 6 テスト）。

共有ヘルパー 3 本（`key` / `entry` / `url`、`:12-24`）は `private` なので、割ると複製か internal 化が要る。

## `ViewerStoreChunkTests.swift`（392 行、@Test 16）

最も明快なのは末尾ブロック `:328-392`（65 行 4 テスト）。「そもそもチャンクに載るか / `fileTooLarge` に落ちるか」という `ViewerStore` のルーティング判定で、**`ChunkedTextReading` を一切使わない**。次点はエラー系（`:160-259`、100 行）で、冒頭の `private final class FailingSecondChunkReader` を使う自己完結した塊。

## 命名の注意

**`Foo+BarTests.swift` の形を使わないこと。** `check-type-group-size.sh` は `base="\${base%%+*}"` でキーを作るため、その形は `FooTests` と合算されず、閾値を名前で回避したことになる（`DocumentCommandController` が実際にその状態）。TASK-431 に倣い `SidebarExpansionSnapshotRootTests` のような別名を使い、**冒頭コメントには行数ではなく「何を検証するか / どこで境界を引いたか」を書く**。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 両グループが 340 行以下になっている
- [x] #2 分割先が Foo+BarTests.swift の形ではなく独立した別名になっている
- [x] #3 各スイートの冒頭コメントが、行数ではなく検証対象と境界の引き方を述べている
- [x] #4 swift test のテスト件数が分割の前後で変わっていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 分割

TASK-431 の方式（別名の独立 @Suite）に従い、`Foo+BarTests.swift` の形は使っていない。

| 元 | 切り出し先 | 境界 |
|---|---|---|
| `SidebarExpansionTests` 399 → **241** | `SidebarExpansionFailureTests` 140 | フォルダの状態が 3 値（`.loaded` / `.loading` / `.failed`）であること（TASK-404）。配列の空さで判定しない規則に属するテストだけ |
| | `SidebarExpansionSnapshotRootTests` 59 | 展開の世代ガードとデータを共有しない。`snapshotRoot` / `snapshotRootCovers` だけを扱い、券も children も出てこない（TASK-481） |
| `ViewerStoreChunkTests` 392 → **327** | `ViewerStoreChunkRoutingTests` 77 | `ChunkedTextReading` を一切使わない。チャンク非対応の種別・サイズ上限・一括読み込みへ落ちる経路だけ |

各スイートの冒頭コメントは「何を検証するか / どこで境界を引いたか」と、
残り 2 つのスイートがどこにあるかを書いてある（行数は書いていない）。

## 共有ヘルパーの扱い

`SidebarExpansionTests` の `key` / `entry` / `url` は `private`（ファイルスコープ）なので、
`SidebarExpansionFailureTests` へは複製した。internal 化しなかったのは、共有すると
`root` の一時パス名まで共有することになり、どちらのスイートが作ったパスかが読めなく
なるため（複製した側の root は `/tmp/SidebarExpansionFailureTests`）。理由はファイル
冒頭の doc に書いてある。`SidebarExpansionSnapshotRootTests` は `root` しか要らないので
複製なし。`ViewerStoreChunkRoutingTests` の `makeStore` / `openAndLoad` は元から共有の
テスト補助なので、そのまま使える。

## 実測

- 型グループ: `check-type-group-size.sh --check` 通過。両グループとも AC #1 の 340 以下
  （327 / 241）。
- `swift test`: **1945 tests**（分割前と同数、AC #4）。スイート数は 320 → 323。
- swiftlint: main とのベースラインより **1 件減った**。
  `ViewerStoreChunkTests.swift` の `type_body_length`（293 行 > 250）が分割で解消した。
  新規の指摘はゼロ。
- swiftformat: 1 ファイルのみ整形（切り出しで生じた空行）。
<!-- SECTION:NOTES:END -->
