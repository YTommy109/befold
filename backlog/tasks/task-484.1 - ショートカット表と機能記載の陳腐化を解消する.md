---
id: TASK-484.1
title: ショートカット表と機能記載の陳腐化を解消する
status: To Do
assignee: []
created_date: '2026-08-14 13:05'
labels: []
dependencies: []
parent_task_id: TASK-484
priority: high
type: task
ordinal: 706000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイトの記載が実装に追いついていない箇所のうち、判断を伴わない機械的なずれを先に潰す。他のサブタスクと独立して進められる。

`site/src/views/features.tsx:26-32` のコメントは、表示モードの `⌘1`〜`⌘3` を「フィーチャーゲートで項目数が変わるため確定するまで書かない」としているが、**そのゲートは 2026-08-14 の #518 で撤去済み**で、コメントと判断が実態に合っていない。表示モードは レンダリング / ソース / 差分 の 3 択で確定している。

また差分レイアウトの上下・左右切替（`⌘\`）もショートカット表に無い。

`site/test/shortcuts.test.ts` が Swift 実装と表記を突き合わせているため、表を増やしたらこのテストも通ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `⌘1` / `⌘2` / `⌘3`（レンダリング / ソース / 差分の切替）がショートカット表にある
- [ ] #2 `⌘\`（差分レイアウトの上下・左右切替）がショートカット表にある
- [ ] #3 features.tsx の FeatureGate を前提としたコメントが削除または実態に合う内容へ直っている
- [ ] #4 日英の両方の表記が更新されている
- [ ] #5 `site/test/shortcuts.test.ts` が通る
<!-- AC:END -->
