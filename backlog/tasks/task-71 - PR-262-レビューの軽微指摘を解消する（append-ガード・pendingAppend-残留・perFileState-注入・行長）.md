---
id: TASK-71
title: 'PR #262 レビューの軽微指摘を解消する（append ガード・pendingAppend 残留・perFileState 注入・行長）'
status: To Do
assignee: []
created_date: '2026-07-19 05:31'
labels: []
dependencies:
  - TASK-68
priority: low
type: chore
ordinal: 700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-19 の PR #262 コーディング規約レビューで見つかった軽微な指摘をまとめて解消する。(1) append 消費経路のガード（BefoldRenderKit/ViewerRenderer+ContentUpdate.swift:90-104）が showLineNumbers を見ないため、同一 revision の pending append と行番号トグルが1つの @Observable サイクルに合体するとトグルが1周期失われうる → ガードに showLineNumbers 一致条件を追加し、不一致なら全文 render に倒す。(2) 直接 HTML モード分岐は pendingAppend 消費前に return するため .html 切替時に pendingAppend が残留しうる（revision 突合で誤 append には至らないが）→ exitDirectHTMLMode でクリアするか、RenderedStateMirror.reset の doc に対象外の理由を明記。(3) ViewerWindowManager.perFileState が値生成デフォルト付きになり、旧 zoomStore の「必須パラメータ注入」（coding_rule.md L299-307）から後退。doc コメント「AppDelegate が単一共有インスタンスを渡す」と実挙動（AppDelegate は渡していない）も不整合 → AppDelegate で明示注入するか doc を実態へ修正。(4) PerFileStateStore の主 init に /// がない。(5) ViewerBridge.swift:87 currentScrollPositionScript が行長 131 文字で SwiftLint 120 warning 超過（既存）。なお (1)(2) が task-68 の描画判定リファクタと同一領域のため、task-68 を先に実施し本タスクはその結果を踏まえて対応すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 append 消費経路が showLineNumbers の変更を取りこぼさない（テストあり）
- [ ] #2 直接 HTML モード切替時の pendingAppend 残留が解消されている（またはミラーの doc に対象外の理由が明記されている）
- [ ] #3 ViewerWindowManager.perFileState の注入方針と doc コメントが実挙動と一致している
- [ ] #4 編集ファイル内の SwiftLint 行長 warning が解消されている
- [ ] #5 既存テストが通過する
<!-- AC:END -->
