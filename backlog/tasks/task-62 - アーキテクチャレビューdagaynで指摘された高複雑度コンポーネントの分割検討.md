---
id: TASK-62
title: アーキテクチャレビュー(dagayn)で指摘された高複雑度コンポーネントの分割検討
status: To Do
assignee: []
created_date: '2026-07-18 23:56'
updated_date: '2026-07-18 23:57'
labels: []
dependencies: []
references:
  - dagayn architecture_analysis_tool(mode=overview/hubs)
  - refactor_tool(mode=suggest)による2026-07-19レビュー
priority: low
ordinal: 900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dagayn の architecture_analysis_tool / refactor_tool(mode=suggest) が、行数・分岐数の観点で分割候補として ViewerStore.swift・ViewerWebView.Coordinator・FileListView.swift・BefoldKit/FileType.swift の4つを split_pressure 上位としてリードした。ViewerStore は TASK-1.4/TASK-29.4 で既に大きくリファクタ済みだが、現時点でも分岐数が高い。各ファイルについて単一責任の観点で分割の要否を評価し、価値がある場合のみ分割する（見送りも可）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerStore.swift(現344行/分岐52) の責務が単一責任原則に照らして評価され、分割するかしないかの判断が記録されている
- [ ] #2 ViewerWebView.swift 内 Coordinator クラス(現674行中約236行/分岐65) について同様に評価・判断されている
- [ ] #3 FileListView.swift(現325行/分岐37) について同様に評価・判断されている
- [ ] #4 BefoldKit/FileType.swift(現178行/分岐48) について同様に評価・判断されている
- [ ] #5 分割を見送った項目には理由(偽の抽象化になる/密結合で効果が薄い等)が記録されている
<!-- AC:END -->
