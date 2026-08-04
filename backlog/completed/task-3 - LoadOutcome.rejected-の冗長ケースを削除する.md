---
id: TASK-3
title: LoadOutcome.rejected の冗長ケースを削除する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 03:16'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/205
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #205 から移行。LoadOutcome の .rejected(RejectReason) は .full(LoadedContent(rejectReason:)) と等価で冗長。apply() で同じ 6 フィールドを設定しており、.rejected は content="" の特殊化に過ぎない。生成箇所は computeLoad の 1 箇所のみ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .rejected ケースが削除され .full で統一されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. LoadOutcome から .rejected ケースを削除
2. computeLoad の .rejected(.unsupportedFormat) を .full(LoadedContent(rejectReason: .unsupportedFormat, content: "")) に変更
3. apply から .rejected 分岐を削除（.full が既に rejectReason を処理している）
4. swift test で既存テスト通過を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LoadOutcome.rejected ケースを削除し、computeLoad の唯一の生成箇所を .full(LoadedContent(rejectReason: .unsupportedFormat, content: "")) に変更。apply の .rejected 分岐も削除。swift test 全321テスト通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.rejected ケースを削除し .full に統一。computeLoad・apply の2箇所を変更。全321テスト通過で既存動作に影響なし。
<!-- SECTION:FINAL_SUMMARY:END -->
