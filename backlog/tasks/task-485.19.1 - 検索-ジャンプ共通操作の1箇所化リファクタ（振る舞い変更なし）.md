---
id: TASK-485.19.1
title: 検索/ジャンプ共通操作の1箇所化リファクタ（振る舞い変更なし）
status: To Do
assignee: []
created_date: '2026-08-21 09:11'
labels: []
dependencies: []
parent_task_id: TASK-485.19
priority: high
ordinal: 775000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find.ts と jump.ts に重複配線されている件数表示・前後移動・close ボタンのクリック配線を
共通モジュールへ1箇所化する準備リファクタ。TASK-485.19 本体（モード統合）に着手する前段。

対象（Explore調査より）:
- 件数表示・前後移動・close の配線パターンは find.ts:468-480 と jump.ts:344-361 で
  ほぼ同じ形が重複している
- navigation.ts は既に move/highlight/count算術を共通化済み（TASK-485.12）。
  今回はイベント配線側の重複を1箇所化する

振る舞いは一切変えない（既存の viewer-main.test.js / viewer-main-jump.test.js が
そのまま緑のままであること）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 件数表示・前後移動・closeボタンのクリック配線が共通モジュールに1箇所化されている
- [ ] #2 find.ts / jump.ts の既存テストが無変更で全て通る（振る舞い変更なし）
<!-- AC:END -->
