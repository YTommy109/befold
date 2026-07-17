---
id: TASK-56
title: TextEncodingTests の Shift_JIS テストデータ構築コピペを共通ヘルパーに整理する
status: To Do
assignee: []
created_date: '2026-07-17 11:50'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。3 つの連続テストが同一の Shift_JIS テストデータ（8KB+ ASCII ヘッダー）をコピペで構築している。共通ヘルパー関数で整理すればテスト意図が明確になり、エッジケース追加時のボイラープレートも不要になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テストデータ構築が共通ヘルパーに集約されている
- [ ] #2 既存テストの検証内容が変わっていない
<!-- AC:END -->
