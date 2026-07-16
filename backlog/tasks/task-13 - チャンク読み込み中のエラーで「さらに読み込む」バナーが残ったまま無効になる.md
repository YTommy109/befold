---
id: TASK-13
title: チャンク読み込み中のエラーで「さらに読み込む」バナーが残ったまま無効になる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:54'
updated_date: '2026-07-16 02:54'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/194'
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
チャンクセッション途中で readNextChunk がエラーを投げると、バナーが表示されたまま反応しなくなりエラーも通知されない。handleLoadMoreLines が nil を受けて早期 return し truncatedScript(false) が JS に送られないため。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 エラー時にバナーが消える、またはエラーメッセージが表示される
- [x] #2 truncation 状態の変化が JS へ伝搬される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.loadMoreLines() の catch ブロックで nil ではなく (chunk: "", isTruncated: false, lineCount: displayedLineCount) を返すように修正
2. guard let session の nil return (セッション競合時) は既存のまま残す — これは正当な no-op
3. テストを追加して修正を検証
4. swift test でリグレッション確認
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.loadMoreLines() の catch ブロックで nil の代わりに空チャンク + isTruncated=false のタプルを返すように修正。これにより Coordinator.handleLoadMoreLines() の guard を通過して truncatedScript(false) が JS に送信され、バナーが消える。全 321 テスト pass。
<!-- SECTION:FINAL_SUMMARY:END -->
