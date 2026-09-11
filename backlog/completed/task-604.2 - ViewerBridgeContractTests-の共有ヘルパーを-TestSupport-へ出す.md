---
id: TASK-604.2
title: ViewerBridgeContractTests の共有ヘルパーを TestSupport へ出す
status: Done
assignee: []
created_date: '2026-09-09 00:01'
updated_date: '2026-09-09 00:26'
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
- [x] #1 共有ヘルパーが ViewerBridgeContractTestSupport（または同等の名前）へ出ている
- [x] #2 3 つの従属スイートが @Suite 型の static ではなく TestSupport を参照している
- [x] #3 ViewerBridgeContractTests グループが 280 行以下になっている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
共有ヘルパー 10 関数 + PostSite + ContractError を新ファイル ViewerBridgeContractTestSupport.swift（enum ViewerBridgeContractSupport）へ切り出した。従属していた 3 スイート（ViewerBridgeCsvNumberFormatTests / ViewerFunctionJumpLanguageContractTests / ViewerJumpLevelContractTests）は @Suite 型の static ではなく ViewerBridgeContractSupport を参照する。

副次的に 3 スイートすべてから @MainActor が外れた。付いていた理由が「借りる ViewerBridgeContractTests の static ヘルパーが @MainActor 隔離のため」だけで、共有面が非隔離の enum になって不要になったもの（ビルドとテストで確認）。@MainActor が残るのは ZoomStore の static 定数を参照する ViewerBridgeContractTests 本体だけ。

実測: 381 → 245 行（AC #3 の 280 以下）。support 側 145 行。swift test 1941 tests / 320 suites 全通過、check-type-group-size.sh exit=0、swiftformat 差分なし、swiftlint の新規指摘なし。
<!-- SECTION:NOTES:END -->
