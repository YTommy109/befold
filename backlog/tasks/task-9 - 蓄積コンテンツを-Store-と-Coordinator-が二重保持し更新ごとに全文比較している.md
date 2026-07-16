---
id: TASK-9
title: 蓄積コンテンツを Store と Coordinator が二重保持し更新ごとに全文比較している
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/200
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #200 から移行。チャンク読み込みで上限 50MB に上がった蓄積テキストを ViewerStore.content と Coordinator.lastRenderedContent が各全量保持（50MB ファイルで Swift 側だけで約 100MB の重複バッファ）。描画ガードが content != lastRenderedContent という全文比較で、updateNSView のたびに O(n) バイト比較がメインスレッドで発生する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lastRenderedContent が世代カウンタまたはハッシュによる変更検知に置き換えられている
- [ ] #2 重複バッファが解消されている
<!-- AC:END -->
