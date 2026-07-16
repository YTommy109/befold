---
id: TASK-14
title: チャンク境界をまたぐブロックコメント・複数行文字列のハイライトが崩れる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:54'
updated_date: '2026-07-16 05:21'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/195'
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
appendChunk がチャンクごとに highlight.js を初期状態で実行するため、チャンク境界をまたぐブロックコメントや複数行文字列の継続部分が通常コードとして誤ハイライトされる。全量描画パスでは問題なく追記パスだけで起きる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 hljs の continuation 状態がチャンク間で引き継がれている
- [x] #2 ブロックコメントがチャンク境界をまたいでも正しく着色される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. appendChunk が新チャンクのみを hljs.highlight() する現状を確認(highlight.js v11 は continuation API 非対応、フルコンテンツ再ハイライトは O(n^2) で性能設計に反するため不採用)。
2. viewer.js: buildLineNumberRows の行分割・span バランス処理を reflowSpanBalancedLines として抽出。
3. viewer.js: codeChunkInnerHtml に任意の contextStr 引数を追加。指定時は contextStr+str をまとめて highlight し、contextStr 分の行を落として返すことでチャンク境界をまたぐコメント/文字列の継続を正しく着色する。
4. viewer.js: lastLines(str, maxLines) を追加。末尾から lastIndexOf を辿るだけで O(maxLines) に文脈行を切り出す(全文スキャンしない)。
5. viewer.html: appendChunk で、直前チャンクが改行終端(=行境界分割)の場合のみ CODE_CHUNK_CONTEXT_LINES(200行)分の文脈を渡す。強制分割(行途中)の既存継続ロジックとは独立させ干渉を避ける。
6. viewer.test.js にブロックコメント継続・文脈除去・lastLines の単体テストを追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
appendChunk で新チャンクのみを孤立して hljs.highlight() していたため、チャンク境界をまたぐブロックコメント/複数行文字列の継続部分が通常コードとして誤ハイライトされていた。単純化検討: (a) 全量再ハイライト方式は appendChunk のドキュメント化済み O(チャンク) 設計方針に反し大きなファイルで性能劣化するため不採用。(b) hljs v11 の continuation API(旧 highlight(lang, code, ignoreIllegals, continuation))は 10.7.0 で廃止済みのため利用不可。(c) 既存の buildLineNumberRows の span バランス処理(行またぎ span を行ごとに自己完結化する仕組み)を再利用し、直前チャンク末尾の固定行数(200行)を文脈として hljs に与えてから文脈分を除去する方式を採用。新規状態変数は増やさず、既存の _lastContent から末尾行を都度切り出すだけで実現。viewer.js の buildLineNumberRows と codeChunkInnerHtml の共通処理を reflowSpanBalancedLines として抽出し重複を排除。強制分割(行途中で終わるチャンク)の既存継続ロジックとは独立させ、_lastChunkEndedWithNewline=true の場合のみ新ロジックを適用。npm test 182件全て pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
appendChunk がチャンク単体で hljs.highlight() していたため、ブロックコメント/複数行文字列がチャンク境界(改行終端の通常分割)をまたぐと継続部分が通常コードとして誤ハイライトされる問題を修正した。直前チャンク末尾200行を文脈として新チャンクと合わせて hljs にかけ、文脈分の行を除去して DOM に追記する方式(lastLines/codeChunkInnerHtml のcontextStr引数/reflowSpanBalancedLines の共通化)を BefoldKit/Resources/viewer.js・viewer.html に実装。全量再ハイライト(O(n^2)で既存の O(チャンク) 設計に反する)や hljs 旧 continuation API(v11で廃止済み)は不採用。強制分割(行途中終端)の既存継続ロジックとは独立させ非干渉。npm test で新規4テストを含む182件全て pass、既存動作に回帰なし。
<!-- SECTION:FINAL_SUMMARY:END -->
