---
id: TASK-604.5
title: ZoomingPDFView から回転アニメの剥がしと検索一致表示を出す
status: To Do
assignee: []
created_date: '2026-09-09 00:02'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: low
ordinal: 881000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/ZoomingPDFView` グループは 392 行（本体 331 + `+Input` 61）。実コードは 155 行で、**doc コメントが 185 行（47%）**。

## 返済先（約 −82 行、392 → 約 310）

**(b) 回転アニメーションの剥がし → `PDFRotationAnimationStripper`（−38、確度 高）**
`ZoomingPDFView.swift:154-191` の `settleRotation`（doc 31 行 + コード 7 行）。**面の stored property を 1 つも読まない**（必要なのは `documentView?.layer` だけ）。内容も PDF の面の責務ではなく CoreAnimation の回避策。`PDFSurfaceRotationTests.rotationLeavesNoLayerAnimations` がそのまま新型を測れる。ここが最も明快。

**(a) 検索の一致表示 → `PDFFindHighlighter`（−44、確度 中）**
`ZoomingPDFView.swift:239-282`。呼び出し元は `PDFFindModel` の 4 箇所のみで、`highlightedSelections` と `go(to:)` は PDFKit の public API なので外の型から書ける。

**ただし設計上の反論がある**: `ZoomingPDFView.swift:3` の型 doc「この面への書き込みはすべてここを通る（TASK-574.1）」が弱まる。移すなら、その不変条件を「倍率・回転・スクロール位置の書き込みは面が持つ」へ**狭めた上で型 doc に書き直す**のが条件。

## 採らない案

`restore(fraction:)`（`:198`）と `scrollSmoothly(by:)`（`:221`）を `PDFSurfaceLayout`（266 行）へ寄せる案は、あちらの「換算だけを持つ」性質を壊し、かつ 300 行超へ押し上げるので採らない。

## 注意

**doc コメントを削るのは返済ではない。** このグループは doc が 47% を占めるので数字だけなら簡単に下がるが、書かれているのは TASK-567 / 572 / 574.1 / 576 の実測と判断。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ZoomingPDFView グループが 330 行以下になっている
- [ ] #2 PDFFindHighlighter を出す場合、型 doc の不変条件が「面が持つ書き込み」の範囲へ狭めて書き直されている
- [ ] #3 doc コメントの削除による行数減が含まれていない（差分で確認できる）
<!-- AC:END -->
