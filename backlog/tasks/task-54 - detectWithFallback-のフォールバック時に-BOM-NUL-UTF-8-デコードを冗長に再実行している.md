---
id: TASK-54
title: detectWithFallback のフォールバック時に BOM/NUL/UTF-8 デコードを冗長に再実行している
status: To Do
assignee: []
created_date: '2026-07-17 11:50'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。detectWithFallback がフォールバック呼び出し時に detectEncodingAndDecode を再度呼ぶが、BOM チェック・NUL スキャン・UTF-8 全ファイルデコードは同じ data に対して同一結果を返す。実際に異なるのは NSString.stringEncoding のステップだけ。50MB の Shift_JIS ファイル等で O(file_size) の無駄な再スキャンが発生する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォールバック時に BOM チェック・NUL スキャン・UTF-8 デコードが重複実行されない
- [ ] #2 既存の TextEncoding テストがすべてパスする
<!-- AC:END -->
