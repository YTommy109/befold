---
id: TASK-10
title: ViewerWebView.swift の evaluateJavaScript 呼び出しでコンパイラ警告が出続けている
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 03:44'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/193
priority: low
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #193 から移行。async コンテキストから evaluateJavaScript(_:completionHandler:) を呼んでいる 3 箇所（ViewerWebView.swift:292-313）で Swift コンパイラが非同期代替関数の使用を提案する警告を毎ビルド出力。意図的な fire-and-forget だがコンパイラは知らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ビルド時にこの警告が出なくなっている
- [ ] #2 既存テストで挙動の変化がないことが確認されている
<!-- AC:END -->
