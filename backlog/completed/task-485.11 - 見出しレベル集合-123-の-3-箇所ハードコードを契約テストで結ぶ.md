---
id: TASK-485.11
title: '見出しレベル集合 {1,2,3} の 3 箇所ハードコードを契約テストで結ぶ'
status: Done
assignee: []
created_date: '2026-08-17 14:04'
updated_date: '2026-08-18 04:33'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 745000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

選択可能な見出しレベル集合 {1,2,3} が 2 言語 3 箇所に独立にハードコードされている。

- Swift: `HeadingJumpLevels` の `(1...3)` フィルタ（`BefoldApp/BefoldKit/HeadingJumpLevels.swift:19`）
- TS: `HEADING_LEVELS`（`viewer-src/jump-providers.ts:18`）
- HTML: 3 つのボタン（`BefoldKit/Resources/viewer.html:61-63`）

言語間の契約テストが無いため、TS/HTML 側だけに h4 を足すと、ユーザーの h4=ON トグルは jumpLevelsChanged → `BridgeMessageRouter.swift:106` → `HeadingJumpLevels` init の経路で `(1...3)` フィルタに黙って落とされ、次のウィンドウで設定が失われる——どのテストも落ちない。`ViewerBridgeContractTests` は `_mmdOpenJump` の存在しか見ていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Swift のフィルタ域と HEADING_LEVELS を結ぶ契約テストがある（またはボタンを HEADING_LEVELS から生成する等、片側変更で壊れない構造にする）
- [x] #2 片側だけレベルを増減するとテストが落ちることを確認する（verify-tests-fail-without-the-fix）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
選べるレベル集合の重複を 3 箇所 → 2 箇所へ減らし、残る 2 箇所を契約テストで結んだ。

- 構造: viewer.html の静的ボタン 3 個を撤去し、jump-providers.ts の buildLevelButtons が HEADING_LEVELS から生成する。Swift 側は [1,2,3] と (1...3) の二重定義を HeadingJumpLevels.selectableLevels 1 つへ寄せた
- 契約テスト: ViewerJumpLevelContractTests（新規）。viewer-bundle.js の HEADING_LEVELS と selectableLevels の一致、および viewer.html にボタンが静的に戻っていないことを検査する。ViewerBridgeContractTests から分けたのは、追加すると file_length 400 行を超えたため（ヘルパー matches / viewerBundleSource / resourceURL を internal へ上げて借りる）
- AC#2 実測: (a) TS のみ [1,2,3,4] → 一致テストが落ちる、(b) Swift のみ [1,2,3,4] → 同テストが落ちる、(c) viewer.html へ静的ボタンを 1 個戻す → HTML ガードが落ちる。3 方向とも確認し元に戻した
- 検証: swift test 1636 passed / npx jest 520 passed / tsc・oxlint・oxfmt・markdownlint 指摘なし / swiftlint 54 件で main のベースラインと同数
- docs/dev/native-app-design.md の文書内ジャンプ節へ「単一の情報源は 2 つだけ」を反映済み
<!-- SECTION:NOTES:END -->
