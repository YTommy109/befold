---
id: TASK-22
title: チャンク境界で行末改行が失われ、行番号なし表示で前後チャンクの行が連結される
status: To Do
assignee: []
created_date: '2026-07-16 10:54'
updated_date: '2026-07-16 12:11'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/BefoldKit/Resources/viewer.js
  - BefoldApp/BefoldKit/Resources/viewer.html
priority: high
type: bug
ordinal: 51
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2 箇所の同型バグ。(1) viewer.js codeChunkInnerHtml の contextStr 経路（~405 行）は reflowSpanBalancedLines が末尾空要素を pop した配列を join するため、チャンク末尾の改行が消える。コード系ファイルのソース表示（行番号 OFF）で 2 回目以降の追記チャンク境界の行が連結される（Node で実証済み: no-context 出力は "\n" 終わり、context 出力は改行なし）。(2) viewer.js csvSourceInnerHtml（346-360 行）も htmlLines.join で末尾改行を出さないため、CSV レインボーソース表示（行番号 OFF）では初回 render→初回追記を含む全チャンク境界で行が連結される。LineChunkReader の通常チャンクは \n 終端（LineChunkReader.swift:106-110）なので消えるのは実データ。修正案: codeChunkInnerHtml の context 戻り値と csvSourceInnerHtml（または appendChunk の非テーブル分岐）で元テキストが \n 終端なら "\n" を復元する。既存テスト（viewer.test.js:951-1008, 776-791）は末尾改行なしのチャンクしか使っておらず未検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コードのソース表示（行番号 OFF）でチャンク境界の行が連結されない
- [ ] #2 CSV ソース表示（行番号 OFF）でチャンク境界の行が連結されない
- [ ] #3 末尾改行付きチャンクを使った回帰テストが viewer.test.js に追加されている
<!-- AC:END -->
