---
id: TASK-485.8
title: stable ビルドの編集メニューに開発中のジャンプ項目が無効状態で常時表示される
status: Done
assignee: []
created_date: '2026-08-17 14:02'
updated_date: '2026-08-18 04:09'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: high
type: bug
ordinal: 714500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: PLAUSIBLE）

`MainMenuBuilder.addDocumentJumpItems`（`BefoldApp/befold/App/MainMenuBuilder.swift:162`）はセパレータと 2 つのジャンプ項目を無条件で挿入し、FeatureGate は検証（validation）でしか無効化しない。stable ビルド（ゲート閉）では `canJump` が常に false（`ViewerCapabilities.swift:80`）のため、ユーザーには「見出しへ移動 / 変更ブロックへ移動」が永久にグレーアウトした壊れた見た目で露出する。TASK-510 がゲートを再導入して防ごうとした露出そのもの。

撤去前のゲートはメニュー構築自体を `if FeatureGate.inProgressFeaturesEnabled` で包んで構築時に隠していた（コミット 85be3c9f）。隣接コメント（`MainMenuBuilder.swift:156-160`）は stable ユーザーへキーバインドを漏らさない意図を示す。一方 task-485.1 の J7 は意図的にゲートを capabilities へ移しており、visible-but-disabled が意図の可能性もある（verdict が PLAUSIBLE 止まりの理由）。

## 方針判断

visible-but-disabled が意図なら、その判断を記録して本タスクは閉じる。意図でなければ、ゲート閉時は項目の構築自体をスキップする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stable ビルド（FeatureGate 閉）の編集メニューにジャンプ項目が表示されない、または表示する判断が理由付きで記録されている
- [x] #2 dev ビルドでは従来どおり項目が表示・動作する
- [x] #3 ゲート閉時の非表示をテストまたは構造（構築スキップ）で担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. build() に isDocumentJumpEnabled: Bool を必須引数で追加し、makeEditMenuItem→addDocumentJumpItems へ伝える（デフォルト引数は付けない）
2. ゲート閉時はセパレータごと構築をスキップする
3. MainMenuCoordinator は FeatureGate.isDocumentJumpEnabled を渡す
4. MainMenuFixture に同引数を通し、ON/OFF 両方のメニュー構築テストを追加する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針判断: visible-but-disabled は意図ではないと判断した。根拠は 2 つ。(1) `ViewerCapabilities.swift:80` の canJump はゲート閉で常に false になるため、項目を出すと stable ユーザーには永久にグレーアウトした項目しか見えない。(2) `MainMenuBuilder.swift` のジャンプ項目直前のコメントが「stable のユーザーへ存在しない機能を告知しない」ためにキー等価を割り当てない旨を明記しており、項目名の露出はその意図と矛盾する。

実装: MainMenuBuilder.build に isDocumentJumpEnabled を**必須引数**で追加し（デフォルト引数を付けると渡し忘れが通る）、ゲート閉では区切り線ごと構築をスキップする。MainMenuCoordinator が FeatureGate.isDocumentJumpEnabled を渡す。
副次: 引数追加で build が 6 引数になり swiftlint の function_parameter_count が新規に鳴いたため、3 つの動的サブメニュー delegate を MainMenuDynamicMenuDelegates へまとめた（MainMenuHelpActions と同じ方針）。

検証: swift test 1634 件パス（ゲート閉テストは if ガードを外すと 3 件の expectation で落ちることを実測済み）。swiftlint は HEAD の git archive 展開ツリーとの差分ゼロ（54→55 になった function_parameter_count を上記のまとめで解消）。swiftformat 適用済み。docs/dev/native-app-design.md の文書内ジャンプ節を「メニュー項目自体を構築しない」へ更新。

補足（実測）: 作業中の swift test が `Fatal error: Attempted to read an unowned reference` で 3 回連続クラッシュしたが、HEAD の展開ツリーでは再現せず、worktree の .build を消して再ビルドしたら解消した。本変更とは無関係な stale ビルド生成物。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
stable ビルド（FeatureGate 閉）で Edit メニューの文書内ジャンプ項目が永久グレーアウトで露出する問題を、構築自体のスキップで解消した。MainMenuBuilder.build がゲートを必須引数で受け取り、閉なら区切り線ごと省く。ゲート開/閉の両方をメニュー構築テストで担保（閉テストはガードを外すと落ちることを実測）。swift test 1634 件パス、swiftlint 差分ゼロ、native-app-design.md を追随。
<!-- SECTION:FINAL_SUMMARY:END -->
