---
id: TASK-44
title: コーディング規約違反を解消する(タスク番号コメント6箇所と新規公開型の /// 欠落)
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 02:08'
updated_date: '2026-07-17 08:41'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 4100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
docs/dev/coding_rule.md の「書かなくてよいコメント: タスク番号や変更履歴の参照(コミットメッセージに書く)」(:406、JS/HTML にも適用 :447)に違反するコメントが本ブランチで6箇所追加された:
- LoadingIndicatorView.swift:5 (task-30)
- ViewerStore.swift:46, 54, 333 (task-32)
- ViewerWebView.swift:455 (TASK-25)
- viewer.html:856 (TASK-25)

また「/// ドキュメンテーションコメント: 公開クラス・公開メソッドに日本語で付ける」(:330)に対し、新規公開型に /// がない:
- NormalizedTextCache.swift: NormalizedTextCacheError(:4)、NormalizedTextCache(:8)、init(data:)(:19)
- StringChunkReader.swift: StringChunkReader(:10)、init(cache:respectsCSVQuotes:)(:18) — 削除された LineChunkReader の型概要 /// も引き継がれていない

タスク番号参照は削除(必要な設計理由はタスク番号なしの言葉で書き直す)し、公開型には日本語の /// を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 プロダクトコード・JS/HTML から task-NN/TASK-NN 参照コメントがなくなる(意図説明は残す)
- [x] #2 NormalizedTextCache/StringChunkReader の公開型・公開イニシャライザに日本語 /// が付く
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. task-NN/TASK-NN 参照コメントを削除し、意図説明は言葉で書き直す: LoadingIndicatorView.swift:5, ViewerStore.swift:45,50,58,339, ViewerWebView.swift:23,458, viewer.html:860
2. NormalizedTextCache.swift の公開型(NormalizedTextCacheError, NormalizedTextCache)と公開イニシャライザ(init(data:))に日本語 /// を追加する
3. StringChunkReader.swift の公開型(StringChunkReader)と公開イニシャライザ(init(cache:respectsCSVQuotes:))に日本語 /// を追加する
4. swift build で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コードレビュー (high) で追加の TASK-39 参照を検出: ViewerStore.swift:45, ViewerWebView.swift:23。AC#1 の対象に含める。

swift build と swift test --skip Integration --skip FileWatcherTests (351 tests) が成功することを確認。grep で対象6箇所+追加検出の TASK-39/ViewerWebView.swift:23 から task-NN/TASK-NN 参照が消えたことを確認。NormalizedTextCache/NormalizedTextCacheError/init(data:)、StringChunkReader/init(cache:respectsCSVQuotes:) に日本語 /// を追加。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
task-NN/TASK-NN 参照コメント(LoadingIndicatorView.swift, ViewerStore.swift x4, ViewerWebView.swift x2, viewer.html)を削除し意図説明を言葉で書き直した。NormalizedTextCache/NormalizedTextCacheError/init(data:) と StringChunkReader/init(cache:respectsCSVQuotes:) に日本語 /// ドキュメンテーションコメントを追加した。swift build 成功、swift test 351件成功、grep で対象ファイルに task-NN/TASK-NN 参照が残っていないことを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
