---
id: TASK-315.2
title: unified diff をパースし、既存の code-table 構造でインライン差分を描画する
status: To Do
assignee: []
created_date: '2026-08-05 14:46'
updated_date: '2026-08-05 14:46'
labels: []
dependencies:
  - TASK-315.1
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 515000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 2 段目。左右分割は次段に回し、まず「1 列で追加・削除・文脈行を並べるインライン（line-by-line）表示」を JS 側に作る。

既存構造を再利用する:

- `viewer.js:334 renderCodeHtml` → `:324 wrapWithLineNumbers` → `:310 buildLineNumberRows` が、行番号 OFF のときも `<table class="code-table">` の 1 行 = 1 `<tr>` を生成する（インデントガイド `--indent-cols` / `--indent-depth` のため）
- ハイライトは `viewer.js:144 highlightCode`（hljs 11.11.1）と `reflowSpanBalancedLines`（行境界で `<span>` を閉じ直す）
- ソース表示の入口は `viewer-main.js:1657 _renderSource`

unified diff のパースは自前で書く（外部ライブラリを入れない方針は TASK-315 に記載）。テストは既存の jest 環境（`BefoldApp/BefoldKit/Resources/__tests__/`）で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 unified diff のパーサがハンク・行種別（追加/削除/文脈）・行番号を正しく返す（jest テストあり）
- [ ] #2 インライン差分が既存の code-table 構造で描画され、行番号・インデントガイド・シンタックスハイライトが従来どおり効く
- [ ] #3 追加・削除の行がライト/ダーク両テーマで区別できる
- [ ] #4 差分が無い場合・パースに失敗した場合に、通常のソース表示へ安全に戻る
<!-- AC:END -->
