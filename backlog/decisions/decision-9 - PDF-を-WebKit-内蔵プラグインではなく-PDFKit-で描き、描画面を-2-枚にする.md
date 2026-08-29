---
id: decision-9
title: PDF を WebKit 内蔵プラグインではなく PDFKit で描き、描画面を 2 枚にする
date: '2026-08-29 11:34'
status: accepted
---
## Context

本文は ADR に置く（`docs/adr/0009-render-pdf-with-pdfkit.md`）。

## Decision

PDF を viewer.html の `<iframe>` + blob URL（WebKit 内蔵 PDF プラグイン）で
描くのをやめ、PDFKit の `PDFView` で描く。pdf.js は採らない。
代償として描画面が 2 枚になるが、宛先の決定は `DocumentSurfaces` に閉じる。

## Consequences

