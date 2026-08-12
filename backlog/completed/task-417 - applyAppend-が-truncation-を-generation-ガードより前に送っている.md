---
id: TASK-417
title: applyAppend が truncation を generation ガードより前に送っている
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:28'
updated_date: '2026-08-11 11:32'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
applyRender 自身の doc コメント（ViewerRenderer+RenderHelpers.swift:105-111）が規則を明記している: 送信とミラー記録は 1 つの同期区間に置く。間で中断されると「送ったが記録していない」状態になり、後続の呼び出しが再送をスキップするため。

applyAppend（同ファイル :55）はこれを破っている。
- :55 webView.evaluateJavaScript(truncation.script) ← 送信
- :63 await embeddedContent(...) ← 中断点
- :66 guard generation == contentUpdateGeneration else { return } ← ガード
- その後 state.truncation = truncation ← ミラー記録

await 中に別の updateContent が generation を上げると、バナー状態は JS へ送信済みなのに rendered.truncation は古い値のまま残る。次の更新の truncation がその古いミラー値と一致すると再送されず、「N 行を表示中」のバナーが実 DOM と食い違ったまま残る。

CLAUDE.md に記録された「描画ミラーの確定漏れ（TASK-320 → 334 → 336）」と同系列。部分更新の送信と確定を同一同期区間へ寄せる形で塞ぐ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 truncation の送信とミラー記録が同一の同期区間に入る（await をまたがない）
- [x] #2 generation が古い呼び出しは JS へ何も送らずに戻る
- [x] #3 送信と記録が分離したら落ちるテストを用意する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. applyAppend の truncation 送信を世代ガードより後ろへ移し、appendChunk 送信・recordRendered と同一の同期区間に並べる
2. applyRender の同位置にある解説と揃う形で、なぜその位置なのかを doc コメントと本文コメントに残す
3. 世代を追い越した applyAppend が JS へ何も送らないこと・世代一致時は送信とミラー確定が同じ呼び出しで起きることをユニットテストで固定する
4. 送信をガードより前へ戻すと落ちることを実際に確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

`ViewerRenderer+RenderHelpers.swift` の `applyAppend` から、`await embeddedContent(...)` より前にあった `webView.evaluateJavaScript(truncation.script)` を削除し、`guard generation == contentUpdateGeneration` より後ろ（appendChunk 送信と `recordRendered` の直前）へ移した。これで applyRender と同じく「送信 → 評価 → 確定」が await を挟まない一続きの同期区間になる。

追い越された呼び出しは JS へ何も送らずに戻るため、ミラーだけが旧値のまま残る状態が作れない。バナーの更新自体は、追い越した側の updateContent が `truncation != rendered.truncation` の判定（applyRender:129）で送るため落ちない。

doc コメントに applyRender と同じ「この位置に並べること」の規則を追記し、本文コメントで TASK-336 / TASK-417 の理由を残した。

## 検証

- `swift test --filter ViewerRendererAppendTruncationTests` → 2 件パス
- **退行検知の確認（AC #3 の実測）**: 送信を `await` より前へ戻した状態で同テストを実行し、
  `世代を追い越された追記は JS へ何も送らない` が
  `Expectation failed: (webView.evaluatedScripts → ["_mmdSetTruncated(true, 200, false)"]).isEmpty → false`
  で失敗することを確認した。確認後に修正へ戻している
- PostToolUse フックによる全体テスト（`swift test --skip Integration --skip FileWatcherTests`、1291 tests / 181 suites）がパス
- swiftformat 実行後に差分なし。swiftlint は `ViewerRenderer+RenderHelpers.swift` の `opening_brace` 1 件のみで、`origin/main` の同ファイルを単体 lint しても同じ 1 件が出るためベースライン差分ゼロ
- 新規ファイル追加のため `xcodegen generate` 実行済み
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
applyAppend の切り詰めバナー送信を世代ガードより後ろへ移し、送信・追記の評価・recordRendered を await を挟まない同一同期区間へ揃えた。追い越された呼び出しは JS へ何も送らずに戻るため「送ったのに記録していない」状態を作れない。ViewerRendererAppendTruncationTests 2 件で固定し、送信をガードより前へ戻すと実際に失敗することを実測で確認した。全体テスト 1291 件パス、swiftlint はベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
