---
id: TASK-318
title: チャンク読み込みの appendChunk が差分テーブルへソース行を混入させる問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:07'
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
- [ ] #1 差分表示 ON のままプログレッシブ読み込みが発生しても、差分テーブルにソース行が混入しない
- [ ] #2 差分表示 OFF に戻した後のチャンク追記は従来どおり動作する
- [ ] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
