---
id: TASK-695
title: WebView の drawsBackground を非公開 KVC から公開 API へ置き換えられるか検証する
status: Done
assignee: []
created_date: '2026-10-09 13:29'
updated_date: '2026-10-12 11:54'
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
- [x] #1 `underPageBackgroundColor` など公開 API で、現行の明暗・透過の挙動(直接 HTML モードを含む)を再現できるかを実測し、結果を Notes に残す
- [ ] #2 再現できる場合は KVC を撤去し、`ViewerCanvasOwnershipTests` と `ViewerRendererOneShotIntegrationTests` が通る
- [x] #3 再現できない場合は KVC を残す理由と、OS 更新で壊れたときに検知する手段(テスト)を Notes に記録して完了する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-12 検証。結論: 公開 API では置換不能、KVC を維持。実測(実 NSWindow に載せたダークアピアランスの WKWebView を takeSnapshot し (10,10) の画素を読む): 既定は a=1、underPageBackgroundColor=.clear のみでも a=1(透過にならない)、KVC drawsBackground=false は a=0、true は a=1、false + underPageBackgroundColor=.red でも a=0。underPageBackgroundColor はオーバースクロール領域の色で、地の描画有無を制御しない。macOS の WKWebView に他の公開の透過手段は無い。既存の ViewerCanvasOwnershipTests は真偽の判定とスタブ面への適用しか見ず、ViewerRendererOneShotIntegrationTests も KVC を読み戻すだけで描画は見ていない。OS 更新で意味が変わる退行を検知できないため、実画素の alpha を見る ViewerCanvasPixelTests を追加した(固定 sleep は didFinish 待ちに置換。キーが消えれば setValue が例外で落ちる)。審査で private API と見なされるリスクは未検証のまま。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
公開 API では現行の透過挙動を再現できないと実測で確認し、KVC を維持。OS 更新での意味変化を検知する ViewerCanvasPixelTests を追加。ViewerCanvasPixelTests / ViewerCanvasOwnershipTests / ViewerRendererOneShotIntegrationTests が通ることを確認。AC #2 は再現不能のため対象外。
<!-- SECTION:FINAL_SUMMARY:END -->
