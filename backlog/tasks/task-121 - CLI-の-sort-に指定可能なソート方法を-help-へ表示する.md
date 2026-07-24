---
id: TASK-121
title: CLI の --sort に指定可能なソート方法を --help へ表示する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-24 04:39'
updated_date: '2026-07-24 04:47'
labels:
  - cli
  - help
dependencies: []
priority: low
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
--help で `--sort <sort>` と表示されるが、指定できる値(folders-first / alphabetical)が --help から分からない。CLISortOrderOption を CaseIterable にして allValueStrings を表示する、または help 文言に候補を明記するなどして、--help だけで指定可能なソート方法が分かるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 --help の --sort 項目で指定可能な値(folders-first / alphabetical)が確認できる
- [x] #2 不正な値を指定した場合のエラーメッセージからも候補が把握できる(可能なら)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLISortOrderOption を CaseIterable に準拠させ、ArgumentParser が --help に候補値(folders-first / alphabetical)を自動表示するようにする
2. 失敗テスト: helpMessage() に候補値が含まれることを確認するテストを追加
3. 実装後、swift test で検証
4. 不正値エラーにも候補が出ることを確認
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLISortOrderOption を CaseIterable に準拠させ、ArgumentParser が --sort の候補値(folders-first / alphabetical)を --help と不正値エラーの両方へ自動表示するようにした。BefoldCLICommandTests に help 表示・不正値エラーの候補確認テストを追加し swift test で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
