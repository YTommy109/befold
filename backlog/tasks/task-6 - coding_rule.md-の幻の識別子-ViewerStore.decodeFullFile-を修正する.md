---
id: TASK-6
title: coding_rule.md の幻の識別子 ViewerStore.decodeFullFile を修正する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 03:26'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/208
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #208 から移行。docs/dev/coding_rule.md:233 の単一情報源テーブルに実在しない ViewerStore.decodeFullFile を委譲元として記載。実際の経路（DefaultFileReader.readString と LineChunkReader）に修正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 該当行が実在の識別子を参照している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
coding_rule.md の2箇所で ViewerStore.decodeFullFile を参照していた。233行: 実在する DefaultFileReader.readString に修正。243行: 具体名を削除し一般化。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
coding_rule.md の幻の識別子 ViewerStore.decodeFullFile を2箇所修正。単一情報源テーブルは DefaultFileReader.readString に、教訓記述は具体名を削除して一般化。
<!-- SECTION:FINAL_SUMMARY:END -->
