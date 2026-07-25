---
id: TASK-152
title: ViewerRenderer のクロージャバンドル 5 個を delegate プロトコルへ移行検討する
status: In Progress
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:45'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
規約に従い、見送り判断の前に実際に delegate 移行を実装して比較する。
1. BefoldRenderKit に @MainActor protocol ViewerRendererDelegate を新設し、5 つのクロージャを weak var delegate 1 本に置き換える（QuickLook 等の静的ホストが省略できる性質は、プロトコル拡張の既定実装＋delegate=nil で維持する）
2. ViewerRenderer+MessageHandling / RenderHelpers / DirectHTMLLinkPolicy の呼び出し側を delegate 経由へ
3. ViewerWebView / ViewerContentView のクロージャ 5 本を delegate 参照 1 本へ畳み、updateNSView の再束縛を消す
4. ViewerWindowController を ViewerRendererDelegate に準拠させ、クロージャ本体をメソッドへ移す
5. テストのクロージャ設定をスタブ delegate へ追従
6. 実装後に「読みやすさ・静的ホストの省略性・テストの書きやすさ」を現行クロージャ方式と比較し、採否を記録する
<!-- SECTION:PLAN:END -->
