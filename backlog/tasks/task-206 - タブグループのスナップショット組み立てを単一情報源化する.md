---
id: TASK-206
title: タブグループのスナップショット組み立てを単一情報源化する
status: To Do
assignee: []
created_date: '2026-07-31 02:49'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowManager.swift
  - BefoldApp/befold/App/SessionRestorer.swift
priority: high
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セッション保存用の TabGroup 組み立て(window.tabGroup?.windows ?? [window] → viewerPath で compactMap → 空なら nil → selectedWindow 決定 → SessionLayout.TabGroup 生成)が ViewerWindowManager.tabGroup(of:)(private)と SessionRestorer.currentSessionLayout() 内の appendGroup の 2 箇所に完全同一の 5 ステップで重複している。「終了時レイアウト」と「Recent Repositories のタブ構成」は同じ形式で保存・相互復元されるため、片方だけ仕様変更(例: selectedPath の決め方)するとサイレントに復元が壊れる。SessionRestorer 側の追加ロジック(seen-set・viewer 判定 guard)は前段に独立しており、組み立て本体の抽出は観測可能な差を生まない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TabGroup スナップショットの組み立てロジックが 1 箇所に統合され、ViewerWindowManager と SessionRestorer の両方がそれを使う
- [ ] #2 セッション保存・復元、Recent Repositories のタブ構成の記録・復元の既存動作が変わらない(既存テストが通る)
- [ ] #3 共通化した組み立てロジックにユニットテストがある
<!-- AC:END -->
