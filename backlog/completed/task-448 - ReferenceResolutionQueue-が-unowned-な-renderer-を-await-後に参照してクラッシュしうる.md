---
id: TASK-448
title: ReferenceResolutionQueue が unowned な renderer を await 後に参照してクラッシュしうる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 13:37'
updated_date: '2026-08-11 14:18'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 100100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #483（TASK-440 の ViewerRenderer 分割）で ViewerRenderer から切り出した ReferenceResolutionQueue が、`private unowned let renderer: ViewerRenderer` を 2 つの suspension point の後ろで参照している（BefoldApp/BefoldRenderKit/ReferenceResolutionQueue.swift:15, :60-77）。

分割前は同じコードが ViewerRenderer 上にあり `Task { @MainActor [weak self] in ... }` の self が renderer 自身だったため、`guard let self` が renderer を強参照して await 後の参照を保証していた。切り出しで self がキューへ変わり、Task が強く保持するのはキューだけになったため、この保証だけが落ちている。

再現経路: JS から `resolveReferences` が来る → キューが応答 Task を開始 → ViewerWindowController → ReferenceResolutionCoordinator.resolveReferences の `Task.detached` で git 参照解決（大きいリポジトリでは数十〜数百 ms）→ その間にユーザーがウィンドウを閉じる（cmd+W）→ ViewerWebView.Coordinator が破棄され ViewerRenderer が deinit → Task 再開時に `guard let self`（= キュー）は成功し、ReferenceResolutionQueue.swift:74 の `renderer.webView` 参照で「Attempted to read an unowned reference but object was already deallocated」でトラップしてアプリが落ちる。

/code-review high の finder + 独立 verifier で CONFIRMED（コード参照で裏付け、実機再現は未実施）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 renderer への参照が await をまたいでも安全な形になっている（weak 化するか、await 前に必要な値を取り切るか、Task が renderer を強参照する形にするかは実装時に決める）
- [x] #2 ViewerRenderer が解放済みの状態で応答 Task が再開しても、トラップせず処理が中断されることをユニットテストで担保している
- [x] #3 同じ形（切り出し先が所有者を unowned で持ち await 後に触る）が BefoldRenderKit の他の切り出し型に無いことを確認し、結果を Implementation Notes に記録している
- [x] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ReferenceResolutionQueue の renderer を weak 化し、各 suspension point の後で生存を確認する
2. ViewerRenderer 解放後に応答 Task が再開してもトラップせず中断することをユニットテストで担保
3. BefoldRenderKit の他の切り出し型（BridgeMessageRouter / ViewerScriptDispatcher / DirectHTMLModeController）に同型が無いか監査し Notes へ記録
4. swift test / swiftlint 差分を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ReferenceResolutionQueue.renderer を unowned → weak にし、応答 Task 内で `guard let self, let renderer` を通してから解決・評価する形にした。応答 Task が強く保持するのはキューだけで renderer は保持しないため（所有は renderer → queue の一方向）、unowned のままだと解決待ちの間にウィンドウが閉じられると再開時にトラップする。

AC#3 の監査結果（BefoldRenderKit の `unowned let renderer` 保持型 4 件）:
- BridgeMessageRouter.swift:18 — await 無し。安全
- DirectHTMLModeController.swift:11 — 完全同期（exit も completion クロージャ方式）。安全
- ViewerScriptDispatcher.swift:10 — await あり。ただし呼び出し元 ViewerRenderer+ContentUpdate.swift:69-70,82-83 が `Task { @MainActor in await self.scriptDispatcher... }` で renderer 自身を強参照キャプチャしており、await 中も renderer は生存する。OneShotRenderer.swift:44 も `private let renderer` で強保持。現状安全だが「呼び出し側が強参照している」という暗黙の前提に依存している
- ReferenceResolutionQueue — 本タスクで修正

検証: swift test 全件 1426 tests / 210 suites 通過。新規テスト ViewerRendererResolveReferencesTests.resolveReferencesStopsWhenRendererIsReleased は、queue だけを残して renderer を解放した状態（#expect(releasedRenderer == nil) で前提を固定）で handle → responseChain を await し、delegate 未呼び出し・評価スクリプト 0 件を確認する。swiftlint は main とのベースライン差分で真の新規ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ReferenceResolutionQueue が持つ ViewerRenderer 参照を unowned から weak へ変え、2 つの suspension point の後で生存を確認してから応答するようにした。renderer 解放済みの状態で応答 Task が再開してもトラップせず中断することを ViewerRendererResolveReferencesTests の新規テストで担保。BefoldRenderKit の他の unowned 保持型 3 件は await 無し、または呼び出し元が renderer を強参照しており同型の穴は無いことを確認（Notes に記録）。swift test 1426 件通過、swiftlint 新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
