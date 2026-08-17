---
id: TASK-485.11
title: '見出しレベル集合 {1,2,3} の 3 箇所ハードコードを契約テストで結ぶ'
status: To Do
assignee: []
created_date: '2026-08-17 14:04'
labels: []
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
- [ ] #1 Swift のフィルタ域と HEADING_LEVELS を結ぶ契約テストがある（またはボタンを HEADING_LEVELS から生成する等、片側変更で壊れない構造にする）
- [ ] #2 片側だけレベルを増減するとテストが落ちることを確認する（verify-tests-fail-without-the-fix）
<!-- AC:END -->
