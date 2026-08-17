---
id: TASK-485.10
title: ショートカットカタログの乖離検知網をジャンプバーの Esc / Enter / Shift+Enter へ拡張する
status: To Do
assignee: []
created_date: '2026-08-17 14:03'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 744000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

TASK-503 で作ったカタログ↔実装の乖離検知網が、ジャンプバーへ拡張されていない。dev ビルドのジャンプバーは Esc / Enter / Shift+Enter に反応する（`viewer-src/keyboard.ts:69-96`）が、`ViewerShortcutCatalog`（`BefoldApp/befold/App/ViewerShortcutCatalog.swift:48`）は Esc を find の閉じる（.findClose）としてしか載せず、Enter / Shift+Enter のジャンプ移動はカタログにも `viewerShortcutCatalog.test.js` にも無い。jest のクロスチェックは `resolveBarCloseKey(key, "find", ...)` しか固定していない。

結果、ヘルプ > キーボードショートカットは Esc の説明を誤り、ジャンプキーを載せず、今後ジャンプキーの挙動を変えてもテストが落ちない——検知網が捕まえるはずの言語間乖離そのもの。カタログ側にゲート機構は無く（`HelpShortcutSections.swift:16-26`）、省略を意図と記録したタスクノートも無い。

注意: FeatureGate との整合（開発中機能のショートカットを stable のヘルプへ出すか）は TASK-485.8 の判断と揃えること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 カタログがジャンプバーの Esc / Enter / Shift+Enter を記載する（FeatureGate との整合方針込み）
- [ ] #2 jest クロスチェックがジャンプ側のキー解決（resolveBarCloseKey の jump 系 / resolveJumpNavigationKey）も固定する
- [ ] #3 ヘルプのショートカット一覧の表示が実装と一致する
<!-- AC:END -->
