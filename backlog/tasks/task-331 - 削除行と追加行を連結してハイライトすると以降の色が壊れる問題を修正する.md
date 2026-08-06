---
id: TASK-331
title: 削除行と追加行を連結してハイライトすると以降の色が壊れる問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:48'
updated_date: '2026-08-06 03:02'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
highlightedDiffLines（viewer.js:422）は hunk 内の全行のテキストを texts.join(\n) で 1 ブロックにしてから hljs にかける。GitDiffReader.wholeFileContextLines（-U1000000）によりファイル全体が単一 hunk になるため、変更行の旧版と新版が隣接し、文字列リテラル・コメント区切り・括弧の途中を編集しただけでレクサ状態が壊れてファイル残り全体が誤った色になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 文字列リテラルを書き換えた差分で、変更行より後のハイライトが通常表示と一致する
- [x] #2 削除行群と追加行群を分けてハイライトする（もしくは同等の方法でレクサ状態の混線を防ぐ）
- [x] #3 修正を戻すと落ちるテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
highlightedDiffLines を旧版(文脈+削除)/新版(文脈+追加)の 2 ブロックに分けてハイライトするよう変更（共通処理は highlightedSideLines へ抽出、文脈行は新版側の結果を採用）。回帰テストは Python の複数行文字列の開始行を書き換える差分で、変更行より後ろの context 行が単独描画と同一 HTML になることを固定。修正を戻すと当該テストと『hljs へは旧版・新版それぞれをまとめて渡す』の 2 件が落ちることを実測（npx jest: 2 failed）。修正後は 380 件全通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
hunk を 1 ブロックにまとめていたハイライトを旧版/新版の 2 ブロックへ分割し、変更行以降の色崩れを解消。npx jest 380 件通過、修正を戻すと 2 件落ちることを実測して確認。
<!-- SECTION:FINAL_SUMMARY:END -->
