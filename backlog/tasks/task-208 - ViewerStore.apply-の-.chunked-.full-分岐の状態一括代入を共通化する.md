---
id: TASK-208
title: ViewerStore.apply の .chunked/.full 分岐の状態一括代入を共通化する
status: To Do
assignee: []
created_date: '2026-07-31 02:55'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/Viewer/ViewerStore.swift
priority: medium
ordinal: 288000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.apply(ViewerStore.swift:305-333)の .chunked / .full 分岐が、同一の skip ガード(dataHash・fileType・loadFailed の比較)と、fileType → contentHash → chunkSession → rejectReason → isTruncated → loadFailed → content → contentRevision → 行数カウンタの 9 フィールド代入列を同一順序で二重に持つ。「表示状態タプルの同時更新」はこのクラスの核心不変条件(297 行目のコメント)であり、フィールド追加時に片分岐だけ更新し忘れる事故を共通ヘルパーで構造的に防ぐ。実差は行数系の扱いのみでパラメータ化できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 skip ガードと状態一括代入が共通ヘルパーに統合され、.chunked / .full の両分岐がそれを使う
- [ ] #2 チャンク読込・全文読込・同一内容 skip の既存挙動が変わらない(既存の ViewerStore テストが通る)
<!-- AC:END -->
