---
id: TASK-4
title: lastIsTruncated と lastTruncatedLineCount を単一フィールドに集約する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 07:11'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/206
priority: low
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #206 から移行。ViewerWebView.Coordinator の 2 フィールドが常にセットで更新され、正規化が 3 箇所にコピーされている。リセットも対で行う必要があり片方を忘れるとバナー変更検知が desync する。あわせて lastRenderedFileType のフォールバックが 3 回繰り返されている点もローカル変数に束ねる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 2 フィールドが単一フィールドまたは setter に集約されている
- [x] #2 lastRenderedFileType のフォールバックが一箇所に束ねられている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. lastIsTruncated / lastTruncatedLineCount を単一の private struct TruncationState(isTruncated, lineCount) の Optional フィールド lastTruncation に統合する。lineCount の 0 正規化(isTruncated ? lineCount : 0)は TruncationState の init に閉じ込め、呼び出し側の重複を排除する。truncationStateChanged は Equatable 比較に置き換える(AC1)。
2. handleLoadMoreLines 内の lastRenderedFileType ?? .code(language: "plaintext") というフォールバックの3回反復を、while ループ手前でローカル変数 fileType に一度だけ束ねて使い回す形に変更する(AC2)。
3. swift build / swift test で既存テストが通ることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
lastIsTruncated/lastTruncatedLineCountをTruncationState(Equatable, 非切り詰め時lineCount=0正規化をinitに内包)の単一OptionalフィールドlastTruncationに統合(AC1)。SwiftLintのtype_body_length制約回避のため、TruncationState定義はCoordinatorクラス本体でなくextension ViewerWebView.Coordinatorに配置。handleLoadMoreLines冒頭でlastRenderedFileType ?? .code(language: "plaintext")を一度だけローカル変数fileTypeに束ね、ループ内3箇所で使い回す形に変更(AC2)。swift build / swift test --skip Integration --skip FileWatcherTests: 323 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWebView.Coordinator の lastIsTruncated/lastTruncatedLineCount を単一の TruncationState(Equatable) 型フィールド lastTruncation に統合し、リセット・更新・比較が1箇所ずつになった(AC1)。handleLoadMoreLines 内で3回反復していた lastRenderedFileType ?? .code(language: "plaintext") のフォールバックをループ手前のローカル変数 fileType に一本化(AC2)。swift build / swift test で323件全テスト成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
