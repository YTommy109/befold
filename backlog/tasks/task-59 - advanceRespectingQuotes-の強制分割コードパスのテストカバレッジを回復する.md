---
id: TASK-59
title: advanceRespectingQuotes の強制分割コードパスのテストカバレッジを回復する
status: To Do
assignee: []
created_date: '2026-07-18 08:13'
updated_date: '2026-07-18 08:14'
labels: []
dependencies:
  - TASK-57
priority: medium
type: chore
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-53 修正時に forcedSplitPreservesQuoteState テスト（1M行・6MB・respectsCSVQuotes:true）が 5K行（30KB）の軽量版に置換され、bytesScanned >= maxChunkBytes の強制分割パスを通るテストがなくなった。また既存の unbalancedQuoteLargeCSVIsChunked テストは 500 バイトクォート回復機能の導入により、チャンクが ~6KB に収まるため byte-limit アサーションが自明に成立するようになり、実質的にテストとして機能していない。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 respectsCSVQuotes:true で maxChunkBytes を超える入力に対する強制分割パスをカバーするテストが存在する
- [ ] #2 unbalancedQuoteLargeCSVIsChunked が 500 バイト回復後のシナリオでも意味のあるアサーションを行う
<!-- AC:END -->
