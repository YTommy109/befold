---
id: TASK-23
title: 内容が同一でもファイル再保存のたびに全再描画される（同一内容スキップの回帰）
status: To Do
assignee: []
created_date: '2026-07-16 10:54'
updated_date: '2026-07-16 12:11'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/befold/Viewer/ViewerStore.swift
  - BefoldApp/befold/Viewer/ViewerWebView.swift
priority: medium
type: bug
ordinal: 50
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 8ef7703 の世代カウンタ化で、ViewerStore.apply(.full)（ViewerStore.swift:264-269）が内容比較なしに contentRevision += 1 するため、touch・エディタのアトミック保存・git checkout 等でバイト同一の内容が再読込されても Coordinator の revision 比較（ViewerWebView.swift:399-404, 351-352）が必ず true になり全 render() が走る。v1.7.0 は content != lastRenderedContent の文字列比較で同一内容をスキップしていた（mermaid 図のちらつき・選択状態の喪失が回帰）。修正案: apply(.full) で loaded.content == content && loaded.rejectReason == rejectReason のとき revision バンプをスキップする（store は content を保持済みなので重複バッファは増えない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一内容のファイル再保存（touch 等）で mermaid 図が再描画されずちらつかない
- [ ] #2 内容が実際に変わった場合は従来どおり再描画される
- [ ] #3 メモリ削減（Coordinator の重複バッファ廃止）は維持される
<!-- AC:END -->
