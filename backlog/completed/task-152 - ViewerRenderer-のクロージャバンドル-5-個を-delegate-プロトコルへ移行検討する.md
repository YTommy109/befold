---
id: TASK-152
title: ViewerRenderer のクロージャバンドル 5 個を delegate プロトコルへ移行検討する
status: Done
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:53'
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
- [x] #1 @MainActor な ViewerRendererDelegate プロトコルへの移行を実装・比較し、採否を記録する
- [x] #2 採用する場合、ViewerRenderer / ViewerWebView / ViewerContentView の 3 層でクロージャ再束縛が解消されている
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実際に delegate 移行を実装して比較し、採用した。

採用の根拠（実装後に確認できた利点）:
- ViewerRenderer の公開面が「オプショナルなクロージャ 5 本」から「weak delegate 1 本」になり、通知先が誰かという問いの答えが 1 箇所になった。
- ViewerWebView / ViewerContentView が受け渡す値が 5 → 1 に減り、updateNSView から 5 本の再代入が消えた（残るのは content・倍率・スクロール位置など毎更新で本当に変わる値だけ）。
- 通知の処理が ViewerWindowController の makeSplitViewController の中に埋まったクロージャ群から、ViewerRendererDelegate 準拠の名前付きメソッド 5 本（MARK 区切り）へ移り、探しやすくなった。
- 規約「クロージャバンドルが 3 つを超えたら delegate を検討」と、既存の SidebarNavigatorHost / ViewerWindowControllerDelegate の流儀に揃った。

実装して初めて分かったコスト（記録として残す）:
- SwiftUI View は struct のため weak を直接持てず、WeakRendererDelegate という箱が要る。これを介さないと 通知先(コントローラ) → window → NSHostingView → View → 通知先 の循環が閉じる。クロージャ版は [weak self] でその場で解決していた部分。
- ViewerRenderer.delegate が weak なので、テストはスタブ delegate をローカル変数で保持し続ける必要がある（保持を忘れると即解放されて通知が届かず、静かに落ちる）。共有スタブ ViewerRendererMessageStubs.Delegate を用意し、各通知をクロージャへ横流しする形で吸収した。
- ViewerContentView に inline で書かれていた onLoadMoreLines（store.loadMoreLines() の呼び出し）はコントローラの rendererDidRequestMoreLines へ移動した。

なお、レビューが挙げた「rename / switch のたびの再束縛が必要」という強い動機自体は、この箇所には元々当てはまっていなかった（クロージャは [weak self] で self 経由参照しており古い値を捕捉していなかったため、再束縛は正しさの条件ではなく SwiftUI の更新に伴う再代入にすぎなかった）。それでも上記の可読性・公開面の単純化が十分な利得と判断した。
静的ホスト（QuickLook 等）が省略できる性質は、プロトコル拡張の既定実装（全メソッド no-op）＋ delegate 未設定で維持している。
検証: swift test 690 tests（Integration 含む）全パス、swift build（SwiftLint 込み）、swiftformat 適用済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerRendererDelegate（@MainActor・全メソッド既定実装あり）を新設し、ViewerRenderer のクロージャ 5 本を weak delegate 1 本へ置き換えた。ViewerWebView / ViewerContentView / ViewerWindowController の 3 層で受け渡しが 1 値になり、updateNSView の再束縛が解消。SwiftUI View が struct であるため WeakRendererDelegate という weak 箱が必要になった点と、テストがスタブ delegate の生存管理を要する点はコストとして記録した。swift test 690 件全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
