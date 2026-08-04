---
id: TASK-49
title: ViewerWebView のタプルと TruncationState 構造体の重複を解消する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 05:10'
updated_date: '2026-07-17 08:48'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 4200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
updateContent/applyRender を通る名前付きタプル (isTruncated, lineCount, loadFailed) が同ファイル内の TruncationState 構造体と同じ構造を持ち、5箇所で手動の展開/再パックが必要。TruncationState を直接パラメータ型として使えば解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 updateContent/applyRender のパラメータが TruncationState 型を直接使用する
- [x] #2 手動の展開/再パック箇所が解消されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. updateContent(truncation:) の型をタプルから Coordinator.TruncationState に変更
2. applyRender(truncation:) も同様に TruncationState に変更
3. 呼び出し元 (updateNSView) で TruncationState を直接構築して渡す
4. truncationStateChanged を TruncationState 同士の比較に変更(手動アンパック除去)
5. applyRender 内の lastTruncation 再構築を代入に置き換え
6. handleLoadMoreLines 内も同様に一度だけ TruncationState を構築して使い回す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
updateContent/applyRender の truncation パラメータを TruncationState 型に変更。truncationStateChanged ヘルパー(手動アンパック)を削除し、TruncationState の Equatable 比較に統一。swift build / swift test --skip Integration --skip FileWatcherTests (351 tests) 通過確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWebView.Coordinator の updateContent/applyRender のパラメータをタプルから TruncationState に変更し、各所での isTruncated/lineCount/loadFailed の手動展開・再パックを解消した。truncationStateChanged ヘルパーは TruncationState 同士の Equatable 比較に置き換わり不要になったため削除。swift build と swift test (351 tests) が通過することを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
