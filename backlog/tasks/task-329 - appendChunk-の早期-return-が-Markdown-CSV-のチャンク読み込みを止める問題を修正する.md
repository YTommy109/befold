---
id: TASK-329
title: appendChunk の早期 return が Markdown/CSV のチャンク読み込みを止める問題を修正する
status: To Do
assignee: []
created_date: '2026-08-06 01:47'
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
- [ ] #1 差分表示 ON の状態で大きな変更済み .csv / .md を開いても 2 チャンク目以降が DOM に追加される
- [ ] #2 判定を「差分テーブルが描画されているか」に変え、差分の有無だけで分岐しない
- [ ] #3 修正を戻すと落ちるテストがある
<!-- AC:END -->
