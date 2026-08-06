---
id: TASK-334
title: applyRender が await 前に diffState を記録し描画がスキップされ得る問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+RenderHelpers.swift:109 の applyRender は await embeddedContent(...) の中断より前に rendered.diffState = diffState を記録する。中断中に SwiftUI が updateNSView を再入すると、updateContent は他の入力が同一なら incoming == rendered と判定して描画をスキップし、同時に contentUpdateGeneration を進めるため中断から復帰した applyRender も generation ガードで抜ける。結果として差分テキストは JS 側に入っているのに render() が走らず、他の状態変化があるまでプレーンなソースのままになる。レビューの評定は PLAUSIBLE（再現手順は理屈上のもので実測されていない）。着手時はまず再現可否を確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 再現可否を実測して Notes に記録する（再現しない場合はその根拠を残して見送り可）
- [ ] #2 再現する場合、rendered の更新が実際の描画完了後に行われる（もしくは同等の方法で取りこぼしが起きない）
<!-- AC:END -->
