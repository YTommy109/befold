---
id: TASK-339
title: appendChunk の diff-table スキップ判定がユーザーコンテンツの table に誤反応する問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 05:34'
updated_date: '2026-08-06 06:31'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 511000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

viewer-main.js:1359 の DOM ベースのスキップ判定 `if (diagramWrap.querySelector('table.diff-table')) { return; }` は、markdown-it が html:true で動くため（viewer-main.js:643、サニタイズはデフォルト設定の DOMPurify のみ）、ユーザーの Markdown 内に書かれた生 HTML `<table class="diff-table">` にも一致する。

再現シナリオ: チャンク読み込み対象の大きな Markdown にこの table が含まれると、先頭チャンクの描画後、以降の appendChunk がすべて挿入前に return し、文書が先頭チャンクで黙って途切れる。_mmdDocument には蓄積されるため、表示オプション変更などの全再描画が起きるまで表示されない。TASK-318 / TASK-329 と同系統の appendChunk ガードの副作用。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ユーザーコンテンツに table.diff-table が含まれていてもチャンク追記が継続する
- [x] #2 差分表示中に appendChunk を抑止する本来の目的は維持される（DOM 参照ではなく内部状態で判定する等）
- [x] #3 viewer-main のテストに回帰テストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
appendChunk の抑止判定を DOM 検索（table.diff-table）から内部状態 _mmdDiffInDom へ移した。render() の入口で false に戻し、差分 HTML を組み立てた _renderDiffHtmlIfAvailable だけが true にする。ユーザーコンテンツに同名 table がある場合の回帰テストは修正前に落ち、修正後に通る（jest 381 件グリーン）。
<!-- SECTION:FINAL_SUMMARY:END -->
