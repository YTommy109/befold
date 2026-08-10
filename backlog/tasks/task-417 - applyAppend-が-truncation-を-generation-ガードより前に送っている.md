---
id: TASK-417
title: applyAppend が truncation を generation ガードより前に送っている
status: To Do
assignee: []
created_date: '2026-08-10 07:28'
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
- [ ] #1 truncation の送信とミラー記録が同一の同期区間に入る（await をまたがない）
- [ ] #2 generation が古い呼び出しは JS へ何も送らずに戻る
- [ ] #3 送信と記録が分離したら落ちるテストを用意する
<!-- AC:END -->
