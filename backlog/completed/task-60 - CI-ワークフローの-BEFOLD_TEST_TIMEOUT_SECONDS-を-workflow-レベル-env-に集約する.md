---
id: TASK-60
title: CI ワークフローの BEFOLD_TEST_TIMEOUT_SECONDS を workflow レベル env に集約する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-18 08:14'
updated_date: '2026-07-18 11:51'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
build-and-test（58行目）と thread-sanitizer（110行目）の2つのジョブに BEFOLD_TEST_TIMEOUT_SECONDS: 30 が重複定義されている。値変更時に片方の更新漏れが起こりうる。workflow レベルの env ブロックに移動して一元管理する。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BEFOLD_TEST_TIMEOUT_SECONDS が workflow レベルの env ブロックで1箇所のみ定義されている
- [x] #2 両ジョブ（build-and-test, thread-sanitizer）で環境変数が正しく参照される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
workflow レベルの env ブロックに BEFOLD_TEST_TIMEOUT_SECONDS: 30 を追加し、build-and-test / thread-sanitizer 両ジョブのステップ内 env 定義を削除する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
YAML構文をruby -ryamlで検証。grep で BEFOLD_TEST_TIMEOUT_SECONDS が28行目のworkflowレベルenvブロックのみに1箇所存在することを確認。GitHub Actionsのworkflowレベルenvは全ジョブ・全ステップに自動継承されるため両ジョブとも参照可能。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ci.yml の build-and-test（旧58行目）・thread-sanitizer（旧110行目）に重複していた BEFOLD_TEST_TIMEOUT_SECONDS: 30 を削除し、workflowレベルのenvブロック（19-28行目）に一元化。YAML構文をruby -ryamlで検証し、grepで定義が1箇所のみであることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
