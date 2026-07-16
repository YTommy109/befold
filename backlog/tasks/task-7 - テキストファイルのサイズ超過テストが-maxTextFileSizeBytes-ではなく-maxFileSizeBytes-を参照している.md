---
id: TASK-7
title: テキストファイルのサイズ超過テストが maxTextFileSizeBytes ではなく maxFileSizeBytes を参照している
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/201
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #201 から移行。ContentLoaderTests.swift:25 と ViewerStoreTests.swift:182 がテキストファイルのサイズ上限テストで maxFileSizeBytes（50MB）を使用しているが、実際の判定は maxTextFileSizeBytes（10MB）。50MB > 10MB のためテストは pass するが意図の表現が誤り。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 両テストの基準が ContentLoader.maxTextFileSizeBytes + 1 に変更されている
<!-- AC:END -->
