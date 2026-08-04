---
id: TASK-22
title: チャンク境界で行末改行が失われ、行番号なし表示で前後チャンクの行が連結される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 10:54'
updated_date: '2026-07-16 17:12'
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
- [x] #1 コードのソース表示（行番号 OFF）でチャンク境界の行が連結されない
- [x] #2 CSV ソース表示（行番号 OFF）でチャンク境界の行が連結されない
- [x] #3 末尾改行付きチャンクを使った回帰テストが viewer.test.js に追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
viewer.js の csvSourceInnerHtml と codeChunkInnerHtml(context経路)を修正。元の入力文字列(content/str)が末尾改行を持つ場合のみ join 結果に '\n' を復元する(既存の _lastChunkEndedWithNewline と同じ「呼び出しごとに入力文字列の末尾を見る」パターンを踏襲、新規の永続状態は追加せず)。回帰テストを viewer.test.js に追加(末尾改行あり/なしの両方)。npx jest --silent 193件全パスを確認。TASK-29のNormalizedTextCache刷新後もこのバグは残存していたことを確認済み(調査は Explore サブエージェントに委譲)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
csvSourceInnerHtml と codeChunkInnerHtml(context経路)で、入力文字列が末尾改行を持つ場合に出力へ '\n' を復元するよう修正。既存の endsWith('\n') チェックパターンを再利用し新規状態は追加していない。viewer.test.js に末尾改行あり/なしの回帰テストを追加し、npx jest --silent で193件全パスを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
