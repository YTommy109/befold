---
id: TASK-332
title: 差分ハンク区切り行の colspan が左右分割テーブルの列数と合っていない問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:48'
updated_date: '2026-08-06 03:04'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
renderSideBySideDiffHtml が出す区切り行（viewer.js:538 / :452）は colspan 6（行番号なしなら 4）だが、外側の diff-split テーブルは 1 行あたり 2 セル（各側の td が diff-side-table を内包する）しかない。ブラウザは 6 列としてレイアウトするため .diff-split .diff-side { width: 50% } が効かず左右のコード列が潰れる。-U1000000 により本番では通常 1 hunk なので露出は限定的だが、同梱の TWO_HUNK_DIFF フィクスチャで再現する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 複数 hunk の差分を左右分割で描画したとき左右のペインが 50% ずつになる
- [x] #2 区切り行の colspan が実際の列数と一致することをテストで固定する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
renderSideBySideDiffHtml の区切り行 colspan を 6/4 から常に 2 へ変更（外側 diff-split テーブルは 1 行あたり左右 2 セルのみで、行番号・記号・内容は各側の内側テーブル diff-side-table に入るため）。テストは colspan=2 の固定に加え、外側テーブルの td 数（'<td class="diff-side ' の出現数）を数えて 1 行あたり 2 セルであることを併せて検証し、colspan と実列数の一致を担保する。旧テストは 6/4 を期待しており、バグをそのまま固定していたため書き換えた。npx jest 380 件通過。AC#1（左右 50%）は style.css:354 の .diff-split .diff-side { width: 50% } が外側テーブルの列数一致を前提とする点をコード参照で確認したもので、実ブラウザでのレンダリング実測は行っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
左右分割の区切り行 colspan を外側テーブルの実列数（常に 2）へ修正し、colspan と実列数の一致をテストで固定。npx jest 380 件通過。
<!-- SECTION:FINAL_SUMMARY:END -->
