---
id: TASK-318
title: チャンク読み込みの appendChunk が差分テーブルへソース行を混入させる問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:07'
updated_date: '2026-08-05 16:42'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 502000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

viewer-main.js:1395 の appendChunk は 'table.code-table' セレクタで追記先テーブルを探すが、差分テーブル（class は 'code-table diff-table'）にもマッチする。プログレッシブ読み込み（truncated ファイル）対象の変更ありファイルを差分表示 ON で開くと、初回描画は差分テーブルになり、スクロールで追加チャンクが届いた時点で appendChunk が通常の 1 ガター構成のソース行 tr を差分テーブル（マーカー + 二重ガター構成）へ挿入する。列がずれた壊れたテーブルになり、codeTable.rows.length から計算する startLine も差分行・hunk ヘッダ行を数えるため行番号が狂う。

同根の箇所: viewer-main.js:1560（_renderCode の diff 分岐）、ViewerRenderer+RenderHelpers.swift:159（canConsumePendingAppend が diff 表示中でも append を許す）。差分表示中は append を抑止する（または diff-table を追記対象から除外する）方向で直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分表示 ON のままプログレッシブ読み込みが発生しても、差分テーブルにソース行が混入しない
- [x] #2 差分表示 OFF に戻した後のチャンク追記は従来どおり動作する
- [x] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

セレクタを `table.code-table:not(.diff-table)` に変える案（追記先を見つけられず return する）と、差分表示中は追記そのものを止める案を比べた。前者は「なぜ追記されないか」がセレクタの否定条件に埋もれ、差分テーブル以外の新しいテーブルが増えるたびに同じ抜けが再発する。後者は理由が 1 行の条件として残り、状態も増えない（既存の `_mmdViewOptions.diff()` をそのまま読む）ため後者を採った。

## 修正

appendChunk の `_mmdDocument.append(text)` の**直後**に `if (_mmdViewOptions.diff() !== null) { return; }` を置いた。順序が要点で、蓄積より前に return すると、蓄積済み内容から描き直す経路（カラースキーム変更、viewer-main.js:631）で追記分が失われる。

## 検証

- jest 373 green（新規 2 件）
- **テストが空振りしていないことを 2 通りで確認**:
  - ガードを削除 → 「差分表示中はチャンクを DOM へ追記しない」だけが落ちる
  - ガードを append より前へ移動 → 「差分表示中に追記したチャンクも蓄積されている」だけが落ちる
  - いずれも戻して 373 green
- 当初書いた「差分を解除すると追記分を含めて描き直される」は、テスト側が全文を render に渡すため蓄積を検証できておらず空振りだった。カラースキーム変更（蓄積済み内容から描き直す実経路）を使う形へ書き換えた
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分テーブルも class に code-table を持つため追記先セレクタに一致し、通常のソース行が差分テーブルへ混入していた。差分表示中は DOM への追記自体を止める形で修正し、蓄積（_mmdDocument.append）は従来どおり続ける。セレクタ側で除外する案は、新しいテーブルが増えるたびに同じ抜けが再発するため採らなかった。検証は jest 373 green（新規 2 件）と、ガードの削除・位置ずらしでそれぞれ対応するテストだけが落ちることの実測。
<!-- SECTION:FINAL_SUMMARY:END -->
