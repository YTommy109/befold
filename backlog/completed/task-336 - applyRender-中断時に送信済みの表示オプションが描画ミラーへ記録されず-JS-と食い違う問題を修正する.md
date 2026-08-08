---
id: TASK-336
title: applyRender 中断時に送信済みの表示オプションが描画ミラーへ記録されず JS と食い違う問題を修正する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-06 05:33'
updated_date: '2026-08-06 06:02'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

applyRender は await 前に diff/行番号/viewMode のスクリプトを WebView へ送信するが（ViewerRenderer+RenderHelpers.swift:104-119）、世代ガードで中断された呼び出しは recordRendered に到達せず、送信済みの値が描画ミラーへ記録されない。以後の applyRender は「ミラーと同値なら再送しない」判定で送信をスキップし、JS 側（_mmdViewOptions）が中断時の値を保持し続ける。

再現シナリオ: 描画中に「差分を表示」を ON→OFF する。呼び出し #1 が setDiff(D) を送って suspend、OFF 側は incoming == rendered で early return、#1 は世代ガードで中断し記録なし。メニューは OFF なのに、次の描画（保存によるライブリロード等）で古い差分テーブルが描かれる。showLineNumbers / isSourceMode も同型（:105-112）。TASK-334（await 前の diffState 記録）の残穴。

併せて対応（PLAUSIBLE 指摘）: フィールド個別更新の recordRendered(contentRevision:fileType:filePath:) オーバーロード（同 :159）が全状態版 recordRendered(_:) と並存し、direct-HTML 経路（ViewerRenderer+ContentUpdate.swift:121）は部分更新 + 個別の rendered.isSourceMode 変更を続けている。TASK-320 / TASK-334 で 2 度直した「確定漏れ」クラスを構造的に塞ぐため、部分更新オーバーロードの撤去を同時に検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 描画中に差分表示等の表示オプションを切り替えても、次回描画後の JS 側オプションが最新のユーザー設定と一致する
- [x] #2 中断された applyRender の送信とミラーの不整合を再現する回帰テストがあり、修正を戻すと落ちる
- [x] #3 recordRendered の部分更新オーバーロードを撤去する。残す場合は direct-HTML 経路の確定漏れが起きないことを構造またはテストで担保し、理由を Notes に記録する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. applyRender の表示オプション送信（lineNumbers / viewMode / diff / truncation）を await と世代ガードより後ろ、render スクリプト評価の直前へ移す。送信と recordRendered の間に suspension point が無くなるため、中断された呼び出しは何も送らず、送った呼び出しは必ず記録される（新しい状態を足さずに不変条件を回復する）。
2. diffState の読み出しも移動後の位置で行う（await 中に変わっていれば世代ガードで抜けるため等価かつ最新）。
3. 中断経路でミラーと JS が食い違わないことを検証する回帰テストを追加し、修正を戻すと落ちることを確認する。
4. 部分更新 recordRendered(contentRevision:fileType:filePath:) を撤去し、direct-HTML 経路を全状態版へ寄せる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: applyRender の表示オプション送信(lineNumbers / viewMode / diff / truncation)と scrollKey 予告を、embeddedContent の await と世代ガードより後ろへ移し、render 評価・recordRendered と同じ同期区間に閉じ込めた。新しい状態は足していない(単純化の検討結果: 送信済みフラグや二重ミラーを新設せず、送信と確定の間から suspension point を取り除くだけで不変条件が回復する)。

recordRendered の部分更新オーバーロード(contentRevision:fileType:filePath:)は撤去し、確定の入口を全状態版 1 つに統一。唯一の呼び出し元だった direct-HTML 経路(ViewerRenderer+ContentUpdate.swift)は、現在の rendered を複製して 4 フィールドだけ書き換えてから渡す形へ寄せた(applyAppend と同じ書き方)。

検証:
- 回帰テスト ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS を追加。実 WKWebView で描画中に差分 ON→OFF を起こし、JS の _mmdViewOptions.diff() を直接読む。
- 修正を戻す(送信を await 前へ戻す)と当該テストが失敗することを実測で確認済み。
- 同テスト内に positive control を置き、差分を実際に反映させると同じ式が本文を返すことを確認(JS を読めていないだけの空振りではない)。
- swift test: 1168 tests / 173 suites すべて成功。
- swiftlint: main ベースラインに対する新規警告ゼロ(既存の function_body_length が 92→93 行に増えたのみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
applyRender の表示オプション送信を await より後ろへ移し、送信・render 評価・ミラー確定を同一の同期区間へ閉じ込めた。中断された呼び出しは何も送らないため、JS 側に中断時の値が残らない。あわせて recordRendered の部分更新オーバーロードを撤去し、確定の入口を全状態版 1 つに統一した(確定漏れを構造的に塞ぐ)。実 WKWebView で JS の保持値を直接読む回帰テストを追加し、修正を戻すと落ちることを実測で確認。swift test 1168 件成功、swiftlint 新規警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
