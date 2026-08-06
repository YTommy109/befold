---
id: TASK-329
title: appendChunk の早期 return が Markdown/CSV のチャンク読み込みを止める問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:47'
updated_date: '2026-08-06 02:02'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 501000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
appendChunk（viewer-main.js:1355）は _mmdViewOptions.diff() !== null、つまり「差分が存在するか」で早期 return する。実際に判定すべきは「差分テーブルが画面に出ているか」。refreshDiff はファイル種別・表示モードを問わず差分を取得するため、tracked かつ変更済みの .md / .csv でも diffText が非 nil になり、差分表示が一度も行われないこれらのファイルでチャンク追加が全て捨てられる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分表示 ON の状態で大きな変更済み .csv / .md を開いても 2 チャンク目以降が DOM に追加される
- [x] #2 判定を「差分テーブルが描画されているか」に変え、差分の有無だけで分岐しない
- [x] #3 修正を戻すと落ちるテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
判定を `_mmdViewOptions.diff() !== null` から `diagramWrap.querySelector('table.diff-table')` へ変更（viewer-main.js:1355 付近）。新しい状態は増やさず、実際の DOM を見る形にした。差分テーブルは `_renderDiffHtmlIfAvailable` 経由で必ず #diagram-wrap 配下に入るため、これが唯一の判定点になる。検証: viewer-main-diff.test.js に md（レンダリング表示）/ csv の追記テストを追加。修正を旧条件へ戻すと 2 件とも落ちることを実測済み（Tests: 2 failed, 8 passed）。修正後は 4 スイート 379 件すべて green。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
appendChunk の早期 return を「差分が存在するか」から「差分テーブルが描画されているか」（DOM 判定）へ変更し、差分表示を行わない .md（レンダリング表示）/ .csv でチャンク追記が全て捨てられる問題を修正した。viewer-main-diff.test.js に回帰テスト 2 件を追加し、修正を戻すと落ちることを確認、npx jest 379 件 green。
<!-- SECTION:FINAL_SUMMARY:END -->
