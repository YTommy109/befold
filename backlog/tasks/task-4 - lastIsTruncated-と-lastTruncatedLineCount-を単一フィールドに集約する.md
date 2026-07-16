---
id: TASK-4
title: lastIsTruncated と lastTruncatedLineCount を単一フィールドに集約する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 03:44'
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
- [ ] #1 2 フィールドが単一フィールドまたは setter に集約されている
- [ ] #2 lastRenderedFileType のフォールバックが一箇所に束ねられている
<!-- AC:END -->
