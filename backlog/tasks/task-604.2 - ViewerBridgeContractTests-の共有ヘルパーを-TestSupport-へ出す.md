---
id: TASK-604.2
title: ViewerBridgeContractTests の共有ヘルパーを TestSupport へ出す
status: To Do
assignee: []
created_date: '2026-09-09 00:01'
labels:
  - refactor
dependencies:
  - TASK-604.1
parent_task_id: TASK-604
priority: medium
ordinal: 878000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befoldTests/ViewerBridgeContractTests.swift` は 381 行だが、**うち約 130 行（`:252-381`）はスイート本体ではなく共有ヘルパー**（10 関数）。

`matches(of:in:)` / `viewerBundleSource()` / `resourceURL(_:)` は internal static で、**他の 3 スイートが `ViewerBridgeContractTests.` 越しに参照している**。

- `ViewerBridgeCsvNumberFormatTests.swift:10,46`（`@MainActor` の理由コメントまで従属している）
- `ViewerFunctionJumpLanguageContractTests.swift:23,51`
- `ViewerJumpLevelContractTests.swift:24,39,54`

`@Suite` 型の static を他スイートが借りるのは歪みで、**閾値と無関係に直すべき**。リポジトリには既に `ViewerStoreTestSupport` / `ViewerWindowControllerTestSupport` / `QuickOpenModelTestSupport` / `DirectoryListingTestSupport` / `DiffTestSupport` という前例がある。

381 → 約 250 行。

TASK-604.1 が同ファイルのメッセージ名参照 7 箇所を書き換えるため、そちらを先に済ませる（--dep）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 共有ヘルパーが ViewerBridgeContractTestSupport（または同等の名前）へ出ている
- [ ] #2 3 つの従属スイートが @Suite 型の static ではなく TestSupport を参照している
- [ ] #3 ViewerBridgeContractTests グループが 280 行以下になっている
<!-- AC:END -->
