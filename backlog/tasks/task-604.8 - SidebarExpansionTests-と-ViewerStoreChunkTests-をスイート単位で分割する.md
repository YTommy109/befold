---
id: TASK-604.8
title: SidebarExpansionTests と ViewerStoreChunkTests をスイート単位で分割する
status: To Do
assignee: []
created_date: '2026-09-09 00:03'
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
- [ ] #1 両グループが 340 行以下になっている
- [ ] #2 分割先が Foo+BarTests.swift の形ではなく独立した別名になっている
- [ ] #3 各スイートの冒頭コメントが、行数ではなく検証対象と境界の引き方を述べている
- [ ] #4 swift test のテスト件数が分割の前後で変わっていない
<!-- AC:END -->
