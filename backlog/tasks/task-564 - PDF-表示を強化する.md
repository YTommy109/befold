---
id: TASK-564
title: PDF 表示を強化する
status: To Do
assignee: []
created_date: '2026-08-29 00:39'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 814000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

現在 PDF は `viewer-src/renderers.ts` の `_renderPdf` が blob URL を `<iframe>` に渡し、WebKit 内蔵の PDF プラグインに丸投げしている。描画・スクロール・ページ送りはすべてプラグイン内部で起き、アプリ側からは中身が一切見えない。

そのため次の 4 つがいずれも実現できていない。

1. 1 ページが画面にフィットした初期表示と、ページ単位のスクロール範囲
2. 表示位置の記憶（他のファイルへ移って戻ったときの復元）
3. 拡大縮小（既存のズームは iframe の width/height を % で伸ばす代用実装。`viewer-src/zoom.ts` の `pdf-body` 特例にコメントで「CSS zoom が効かない」と明記されている）
4. 90 度単位の向き変更

これらは個別の機能不足ではなく「PDF がブラックボックスの iframe である」という単一の根本原因に由来する。したがって描画方式の差し替えを基盤タスクとして先に置き、その上に 4 機能を積む。

## 採用する方式

**PDFKit（`PDFView`）をネイティブに置く。** 要望の 4 つは `PDFView` の標準機能でほぼそのまま得られる（`displayMode = .singlePage` / `autoScales` / `rotate(byDegrees:)` / `go(to:)` / `currentDestination`）。同梱ライブラリが不要で、描画品質と大きい PDF の性能を Apple 側に預けられる。

代償は描画面が WKWebView と 2 枚になること。ただし PDF は既にソース表示・差分・行番号・検索・ジャンプのいずれも持たない最も退化したケースで（`FileType.isBinaryContent` により `canSelectSourceMode` / `canSelectDiffMode` が false）、ズームも既に iframe 特例のハックになっている。外へ出す方が特例が減る見込み。

採らなかった案: pdf.js を viewer.html に同梱する。既存の zoom/scroll/find 基盤にそのまま乗る利点はあるが、1MB 超のバンドル同梱と、レンダリング品質・大きい PDF の性能を自前で抱えることになる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 4 つのサブタスクがすべて完了している
- [ ] #2 PDF の描画方式の選択が ADR として記録されている
- [ ] #3 `viewer-src/zoom.ts` の `pdf-body` 特例と `renderers.ts` の `_renderPdf` / `_createPdfBlobHolder` が撤去されている
<!-- AC:END -->
