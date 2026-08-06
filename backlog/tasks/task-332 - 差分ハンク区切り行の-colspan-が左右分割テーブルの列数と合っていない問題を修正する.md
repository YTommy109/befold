---
id: TASK-332
title: 差分ハンク区切り行の colspan が左右分割テーブルの列数と合っていない問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:48'
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
- [ ] #1 複数 hunk の差分を左右分割で描画したとき左右のペインが 50% ずつになる
- [ ] #2 区切り行の colspan が実際の列数と一致することをテストで固定する
<!-- AC:END -->
