---
id: TASK-152
title: ViewerRenderer のクロージャバンドル 5 個を delegate プロトコルへ移行検討する
status: To Do
assignee: []
created_date: '2026-07-25 11:31'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI 層レビュー指摘。ViewerRenderer に注入するクロージャが onZoomChanged / onScrollPositionChanged / onOpenReference / onLoadMoreLines に onResolveReferences が加わり 5 個になり、規約閾値「3 つを超えたら delegate プロトコルを検討」を超過。ViewerWebView.updateNSView（L72-76）が毎更新サイクルで全クロージャを再束縛している現状は delegate 移行の動機（weak delegate なら再束縛が消える）に合致する。置換は ViewerRenderer / ViewerWebView / ViewerContentView の 3 層まとめてになる。規約により、見送る場合も代替実装を試して比較した結果を記録すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 @MainActor な ViewerRendererDelegate プロトコルへの移行を実装・比較し、採否を記録する
- [ ] #2 採用する場合、ViewerRenderer / ViewerWebView / ViewerContentView の 3 層でクロージャ再束縛が解消されている
<!-- AC:END -->
