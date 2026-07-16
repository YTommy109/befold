---
id: TASK-8
title: CSV ソース表示の「さらに読み込む」が毎回全文再描画になり O(n²)
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/199
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #199 から移行。CSV をソース（レインボー）表示している場合、「さらに読み込む」のたびに蓄積済みコンテンツ全体を renderScript で再描画している。非 CSV パスは appendChunkScript で O(chunk) の追記になっており、CSV ソースモードも追記パスを使えるように JS 側を拡張する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV ソースモードも追記パス（appendChunk）を使用している
- [ ] #2 全文再描画の特例コードが撤去されている
<!-- AC:END -->
