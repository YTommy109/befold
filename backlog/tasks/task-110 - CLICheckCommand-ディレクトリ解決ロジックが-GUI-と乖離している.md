---
id: TASK-110
title: 'CLICheckCommand: ディレクトリ解決ロジックが GUI と乖離している'
status: Done
assignee: []
created_date: '2026-07-23 12:18'
updated_date: '2026-07-23 13:04'
labels:
  - bug
  - cli
dependencies:
  - TASK-115
priority: high
ordinal: 49500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
defaultResolveFileToOpen はアルファベット順で最初の非ディレクトリファイルを返すが、GUI の DirectoryLister.resolveFileToOpen はサポート形式（.mmd, .md）を優先する。混在ディレクトリで --check の結果が GUI と不一致になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI のディレクトリ解決が GUI と同じサポート形式優先ロジックを使用する
- [x] #2 サポート形式と非サポート形式が混在するディレクトリでの --check テストが存在する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-115(BefoldKit への共通ロジック移設)で解消する方針。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-115 で CLICheckCommand.defaultResolveFileToOpen を BefoldKit.SupportedFileResolver(サポート形式優先)へ委譲する実装に置き換え、DirectoryLister と同一ロジックに統一した。検証: befoldCLITests/CLICheckAndBookmarkDefaultsTests.swift の checkPrefersSupportedFormatInMixedDirectory テスト、swift test 全体(601 tests green)。
<!-- SECTION:FINAL_SUMMARY:END -->
