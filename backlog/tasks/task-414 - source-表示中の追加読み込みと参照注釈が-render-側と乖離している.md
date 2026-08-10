---
id: TASK-414
title: source 表示中の追加読み込みと参照注釈が render 側と乖離している
status: To Do
assignee: []
created_date: '2026-08-10 07:27'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 501500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer-main.js の render() と appendChunk() が同じ関心（表示モードに応じた描画）を 300 行離れた場所でそれぞれ判定しており、同型のズレが 2 件出ている。CLAUDE.md の「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」に該当する。

1. appendChunk が表示モードを見ない（viewer-main.js:1423）: `if (type === "md")` だけで分岐し _mmdViewOptions.mode() を一切参照しない。大きな .md（StringChunkReader が分割し「さらに読み込む」バナーが出るもの）を開き、source 表示に切り替えてから「さらに読み込む」を押すと、Swift 側 applyAppend（ViewerRenderer+RenderHelpers.swift:69）が ViewerBridge.appendChunkScript(chunk:fileType:) で FileType しか渡さないため JS は type === "md" と判断し、md.render(text) の結果を source の <pre><code><table class="code-table"> の下へ insertAdjacentHTML する。行番号のない描画済み Markdown が生ソースの下に挟まり、以降の行番号も連続しない。2 行下の CSV 分岐は同じ事故を避けるために実 DOM（pre code.csv-source）を見に行っており、md だけが漏れている。

2. source 表示でパス参照が注釈されない（viewer-main.js:1707）: render() の source 分岐（:1706-1710）は _renderSource → _mmdRestoreScrollPosition → return で、共通の末尾にある _annotatePathRefs()（:1740）と _mmdResolveReferences()（:1741）へ到達しない。.md の source 表示ではパス文字列がただのテキストになる一方、同じ文字列が .swift（type === "code" は source 分岐から除外され _renderCode 経由で末尾へ到達する）ではクリックできる。さらに同じ source 表示の中でも、チャンク追加後は appendChunk が _walkTextNodes（:1489）と _mmdResolveReferences（:1499）を呼ぶため、追加された行だけリンクになり上の行は死んだままになる。同一文書で 3 通りの挙動になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 source 表示中に「さらに読み込む」を押しても、追加分がソース表示（行番号つき・行番号連続）として追記される
- [ ] #2 source 表示の初回描画でもパス参照が注釈・解決される（.md と .swift で挙動が一致する）
- [ ] #3 チャンク追加の前後でパス参照の挙動が変わらない
- [ ] #4 render と appendChunk が表示モード判定を共有し、片方だけ直せる構造になっていない（判定を複製したら落ちるテスト、または共通経路への一本化）
- [ ] #5 Node テスト（viewer.js 側の純粋ロジック）で表示モード判定を検証する
<!-- AC:END -->
