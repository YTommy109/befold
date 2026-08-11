---
id: TASK-448
title: ReferenceResolutionQueue が unowned な renderer を await 後に参照してクラッシュしうる
status: To Do
assignee: []
created_date: '2026-08-11 13:37'
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
- [ ] #1 renderer への参照が await をまたいでも安全な形になっている（weak 化するか、await 前に必要な値を取り切るか、Task が renderer を強参照する形にするかは実装時に決める）
- [ ] #2 ViewerRenderer が解放済みの状態で応答 Task が再開しても、トラップせず処理が中断されることをユニットテストで担保している
- [ ] #3 同じ形（切り出し先が所有者を unowned で持ち await 後に触る）が BefoldRenderKit の他の切り出し型に無いことを確認し、結果を Implementation Notes に記録している
- [ ] #4 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
