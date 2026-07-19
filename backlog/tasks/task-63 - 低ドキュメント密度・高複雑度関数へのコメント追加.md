---
id: TASK-63
title: 低ドキュメント密度・高複雑度関数へのコメント追加
status: To Do
assignee: []
created_date: '2026-07-18 23:57'
labels: []
dependencies: []
references:
  - dagayn refactor_tool(mode=suggest)による2026-07-19レビュー
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dagayn の refactor_tool(mode=suggest) が document 候補として、説明密度が低く複雑度が高い3関数を挙げた: BefoldKit/Resources/viewer.js::tokenizeCsvRows、befold/App/MainMenuBuilder.swift::makeEditMenuItem、makeViewMenuItem(いずれも分岐/協調呼び出しが多い)。各関数の非自明な意図・前提条件を短いコメントで補足する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer.js の tokenizeCsvRows に、CSVトークナイズの前提(クォート処理方針等)を説明する短いコメントが追加されている
- [ ] #2 MainMenuBuilder.makeEditMenuItem に、メニュー項目構成の意図を説明する短いコメントが追加されている
- [ ] #3 MainMenuBuilder.makeViewMenuItem についても同様にコメントが追加されている
<!-- AC:END -->
