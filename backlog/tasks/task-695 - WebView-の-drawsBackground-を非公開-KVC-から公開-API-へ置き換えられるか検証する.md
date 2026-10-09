---
id: TASK-695
title: WebView の drawsBackground を非公開 KVC から公開 API へ置き換えられるか検証する
status: To Do
assignee: []
created_date: '2026-10-09 13:29'
labels:
  - tech-debt
dependencies: []
references:
  - BefoldApp/BefoldRenderKit/WebKitRenderSurface.swift
  - BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift
priority: low
ordinal: 884000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WKWebView の背景制御に `setValue(_, forKey: "drawsBackground")` の KVC を使っている(`BefoldRenderKit/WebKitRenderSurface.swift` の `setDocumentOwnsCanvas`、`ViewerWebViewFactory.swift`)。非公開キーなので OS 更新で黙って壊れうる。App Store 掲載を検討した調査(2026-10-09)で、審査で private API と見なされるリスクも指摘された(実機審査の実績は未確認)。ただし極性と見た目は `ViewerCanvasOwnershipTests` が実測のピクセル値で固定しており、公開 API(`underPageBackgroundColor` など)で同じ見た目になるかは未確認。検証の結果「置換できない」でもよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `underPageBackgroundColor` など公開 API で、現行の明暗・透過の挙動(直接 HTML モードを含む)を再現できるかを実測し、結果を Notes に残す
- [ ] #2 再現できる場合は KVC を撤去し、`ViewerCanvasOwnershipTests` と `ViewerRendererOneShotIntegrationTests` が通る
- [ ] #3 再現できない場合は KVC を残す理由と、OS 更新で壊れたときに検知する手段(テスト)を Notes に記録して完了する
<!-- AC:END -->
