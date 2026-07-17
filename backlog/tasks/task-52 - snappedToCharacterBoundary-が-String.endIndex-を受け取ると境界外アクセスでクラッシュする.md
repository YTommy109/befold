---
id: TASK-52
title: snappedToCharacterBoundary が String.endIndex を受け取ると境界外アクセスでクラッシュする
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 11:50'
updated_date: '2026-07-17 14:36'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 2500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。advanceByLines または advanceRespectingQuotes が累積バイト数 == maxChunkBytes のとき String.endIndex を snappedToCharacterBoundary に渡しうる。utf8View[endIndex] は境界外アクセスとなり、debug ビルドではクラッシュ、release ビルドでは不正バイトを読んで分割位置が壊れコンテンツが欠落する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 snappedToCharacterBoundary が endIndex を受け取った場合に安全に処理される
- [x] #2 debug ビルドでクラッシュしない
- [x] #3 累積バイト数がちょうど maxChunkBytes に一致するケースのテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 原因: advanceByLines で bytesScanned + lineBytes == maxChunkBytes (行境界ちょうど) かつ
   その行が最終行のとき、rawEnd == cache.text.endIndex となる。
   snappedToCharacterBoundary は index > lowerBound を満たす限り utf8View[index] を
   無条件に読むため、index == endIndex (= utf8View.endIndex) のとき境界外アクセスでクラッシュする。
2. 単純化検討: 新しい状態や分岐追加ではなく、既存の utf8View を使い
   ループ条件に `index < utf8View.endIndex` を追加するだけで一般化して解決できる
   (endIndex は定義上すでに文字境界のため、その場合はスナップ不要で早期終了するのが自然)。
   専用のendIndex特別扱いコードを足すより単純。
3. StringChunkReaderTests.swift に、累積バイト数がちょうど maxChunkBytes に一致する
   ケース(最終行がぴったり境界に来る、かつ末尾が endIndex になるケース)のテストを追加する。
4. 実装: snappedToCharacterBoundary のwhileループ条件に index < utf8View.endIndex を追加する。
5. swift test で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
修正: snappedToCharacterBoundary の while ループ条件に index < utf8View.endIndex を追加。endIndex は定義上すでに文字境界のためスナップ不要で、境界外アクセスを避けられる。テスト: 改行なしテキストの長さがちょうど maxChunkBytes のケースを追加し、修正前にクラッシュすることを確認済み。swift test --skip Integration --skip FileWatcherTests で 352 件全て pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
advanceByLines が最終行の累積バイト数をちょうど maxChunkBytes に一致させると rawEnd が cache.text.endIndex になり、snappedToCharacterBoundary が utf8View[endIndex] を読んで境界外アクセスでクラッシュしていた。修正は既存の utf8View を使い while ループ条件に index < utf8View.endIndex を追加するのみ(新規状態・特別分岐なし)。StringChunkReaderTests に exactMaxChunkBytesNoTrailingNewlineDoesNotCrash を追加し、修正前にクラッシュ・修正後に pass することを確認。swift test --skip Integration --skip FileWatcherTests で 352 件全て pass。
<!-- SECTION:FINAL_SUMMARY:END -->
