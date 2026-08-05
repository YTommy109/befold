---
id: TASK-208
title: ViewerStore.apply の .chunked/.full 分岐の状態一括代入を共通化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:55'
updated_date: '2026-07-31 07:24'
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
- [x] #1 skip ガードと状態一括代入が共通ヘルパーに統合され、.chunked / .full の両分岐がそれを使う
- [x] #2 チャンク読込・全文読込・同一内容 skip の既存挙動が変わらない(既存の ViewerStore テストが通る)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. apply() の表示状態 9 フィールドを private struct DisplayState として定義する(実差の行数系は tracksLineCount フラグでパラメータ化)
2. skip ガード + 一括代入を applyDisplayState(_:) -> Bool に統合する
3. apply() は switch で DisplayState を組み立てるだけにし、書き換えは applyDisplayState 1 箇所へ一本化する
4. .chunked の同一内容スキップの特性テストを追加し、既存 ViewerStore テストで挙動不変を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DisplayState 構造体 + applyDisplayState(_:) で skip ガードと 9 フィールド代入を一本化。実差は tracksLineCount のみ(.chunked=true で newlineCount 再計算、.full=false でカウンタ 0 リセット)。skip 条件は元の .chunked/.full と等価(contentHash が非 nil かつ一致 && fileType 一致 && !loadFailed)。ViewerStoreChunkTests に .chunked 同一内容スキップの特性テストを追加。swift build / swift test で 906 tests 全通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.apply の .chunked/.full 分岐にあった同一の skip ガードと 9 フィールド一括代入を、private struct DisplayState と applyDisplayState(_:) -> Bool に統合した。apply() は switch で DisplayState を組み立てるだけになり、表示状態の書き換えは applyDisplayState の 1 箇所に一本化されたため、フィールド追加時の片側更新漏れが構造的に起きなくなった。実差である行数カウンタの扱いは tracksLineCount フラグでパラメータ化している。挙動不変は既存 ViewerStore テスト群 + 追加した .chunked 同一内容スキップの特性テストで確認(swift build 成功、swift test 906 tests 全通過)。
<!-- SECTION:FINAL_SUMMARY:END -->
