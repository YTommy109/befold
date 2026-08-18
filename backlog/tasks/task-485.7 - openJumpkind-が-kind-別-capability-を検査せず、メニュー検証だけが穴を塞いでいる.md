---
id: TASK-485.7
title: 'openJump(kind:) が kind 別 capability を検査せず、メニュー検証だけが穴を塞いでいる'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-17 14:02'
updated_date: '2026-08-18 02:29'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 714800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`WebViewCommandController.openJump(kind:)`（`BefoldApp/befold/App/WebViewCommandController.swift:114`）は粗い `capabilities().canJump` しか guard せず、kind 別の規則（changeBlock は showsDiff が必要）はメニュー検証（ViewerMenuValidator）だけで守られている。`ViewerCapabilitiesFactory.swift:39-41` は「メニュー検証とコマンド guard の両方を capability で閉じる」と述べており、実装と矛盾する。

per-kind API 自体は存在する（`ViewerCapabilities.canJump(to:)`、`ViewerCapabilities.swift:103-107`）が、コマンド経路の誰も呼んでいない。kind は `DocumentRendering.swift:39` / `WebViewDocumentRenderer.swift:68` を生 String で通るため、コンパイラは per-kind 検査を強制できない。

再現シナリオ: 差分表示中にメニューが「変更ブロックへ移動」を有効と検証 → メニュー追跡中に file watcher 由来の更新で plain source へフォールバック（showsDiff=false）→ クリックが粗い guard を通過し、非差分ビューに 0/0 の changeBlock バーが開く。レース自体は稀で結果も良性（0/0 バー）だが、将来の非メニュー入口（stable 昇格時のキーバインド・ツールバー）が同じ穴を継承する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コマンド経路（openJump）が kind 別 capability で閉じている
- [x] #2 showsDiff=false のとき changeBlock ジャンプが開かないことをテストが固定する
- [x] #3 将来の入口が per-kind 検査を迂回できない構造（生 String 渡しの見直しを含めて検討する）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. DocumentRendering.openJump の引数を String から DocumentJumpKind へ変える(両者とも befold ターゲット内なので依存は増えない)。生 String は WebViewDocumentRenderer が ViewerBridge.openJumpScript へ渡す 1 箇所だけに閉じる。
2. WebViewCommandController.openJump の guard を capabilities().canJump(to: kind) へ差し替える。
3. ViewerWindowController+MenuActions は kind.rawValue をやめ kind をそのまま渡す。
4. テスト: showsDiff=false のとき changeBlock ジャンプが JS へ届かず heading は届くことを WebViewCommandControllerTests へ追加する。修正を戻すと落ちることを確認する。
5. swift build / swift test / swiftlint ベースライン差分ゼロを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: DocumentRendering.openJump / WebViewCommandController.openJump / ViewerWindowController+MenuActions の引数を String から DocumentJumpKind へ変え、コマンド経路の guard を capabilities().canJump(to: kind) にした。生 String は JS 境界の WebViewDocumentRenderer が ViewerBridge.openJumpScript(kind:) へ渡す 1 箇所だけに閉じた（ViewerBridge は BefoldKit にあり DocumentJumpKind を知らないため、そこは String のまま）。

単純化の検討: 新しい状態や述語は足していない。既に存在していた per-kind API（ViewerCapabilities.canJump(to:)）を呼ぶだけで塞がる形だったので、型を DocumentJumpKind へ変えて「呼ばないと書けない」構造にした（AC #3 の生 String 渡しの見直し）。

検証（実測）:
- swift build: Build complete
- swift test: 1632 tests / 260 suites すべて成功
- 修正を戻して確認: guard を canJump へ戻すと「変更ブロックへのジャンプは差分表示でないとき JS へ届かない」が openJump(kind: .changeBlock) を記録して失敗する（もう 1 本は通る）。テストが空振りしていないことを確認済み
- swiftlint ベースライン差分: main / HEAD ともに 54 件、真の新規ゼロ・解消ゼロ
- markdownlint-cli2: 0 issues

docs/dev/native-app-design.md の文書内ジャンプ節へ、コマンド経路が DocumentJumpKind を運び canJump(to:) で閉じることを追記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
コマンド経路が種類別 capability を迂回できないよう、openJump の引数を生の String から DocumentJumpKind へ変え、guard を ViewerCapabilities.canJump(to:) にした。文字列化は JS 境界 1 箇所へ閉じたので、将来の非メニュー入口（キーバインド・ツールバー）も per-kind 検査を通らずには書けない。showsDiff=false で changeBlock ジャンプが JS へ届かないことを WebViewCommandControllerTests の 2 本で固定し、修正を戻すと失敗することも確認した（swift test 1632 件成功、swiftlint 新規違反ゼロ）。
<!-- SECTION:FINAL_SUMMARY:END -->
