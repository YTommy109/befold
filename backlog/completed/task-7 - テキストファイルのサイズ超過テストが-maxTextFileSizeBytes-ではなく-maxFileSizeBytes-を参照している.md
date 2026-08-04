---
id: TASK-7
title: テキストファイルのサイズ超過テストが maxTextFileSizeBytes ではなく maxFileSizeBytes を参照している
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 03:29'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/201
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #201 から移行。ContentLoaderTests.swift:25 と ViewerStoreTests.swift:182 がテキストファイルのサイズ上限テストで maxFileSizeBytes（50MB）を使用しているが、実際の判定は maxTextFileSizeBytes（10MB）。50MB > 10MB のためテストは pass するが意図の表現が誤り。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 両テストの基準が ContentLoader.maxTextFileSizeBytes + 1 に変更されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ContentLoaderTests.swift:25、ViewerStoreTests.swift:182、ViewerStoreTests.swift:215 の3箇所を maxTextFileSizeBytes に修正。352行の .png テストは maxFileSizeBytes で正しいため変更なし。全321テスト通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
テキストファイルのサイズ超過テスト3箇所で maxFileSizeBytes を maxTextFileSizeBytes に修正。バイナリファイルのテスト(352行)は正しいため変更なし。
<!-- SECTION:FINAL_SUMMARY:END -->
