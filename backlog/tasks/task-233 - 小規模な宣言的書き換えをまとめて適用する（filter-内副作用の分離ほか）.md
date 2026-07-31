---
id: TASK-233
title: 小規模な宣言的書き換えをまとめて適用する（filter 内副作用の分離ほか）
status: To Do
assignee: []
created_date: '2026-07-31 09:16'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 400000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
調査で挙がった小粒の命令的コードを宣言的に書き換える。(1) SessionRestorer.swift:108-122 — filter の述語内で onMissing を呼ぶ副作用を分離し、restoredPaths の構築もループから導出値に分ける（lazy 化などで noteClosed が呼ばれなくなる潜在バグの予防）。(2) ReferenceResolutionCoordinator.swift:86-93 — var 辞書 + ループを compactMapValues に。(3) GitRepository.swift:99-109 — gitdir 行探索を first(where:) + 解釈の分離に。(4) NavigationHistory.swift:80-92 — 隣接重複除去と index 補正の絡み合いを「生き残る index 集合」からの導出に。(5) HistoryButtonView.swift:96-107 — タイトルだけ分岐しアイコン生成は共通、という構造を明示化。いずれも挙動不変のリファクタで 1 PR にまとめられる規模。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対象 5 箇所が宣言的な形に書き換えられ、既存テストが通る
- [ ] #2 SessionRestorer の欠損ファイル通知（noteClosed 経路）が純粋な filter と分離されている
<!-- AC:END -->
