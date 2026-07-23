---
id: TASK-110
title: 'CLICheckCommand: ディレクトリ解決ロジックが GUI と乖離している'
status: To Do
assignee: []
created_date: '2026-07-23 12:18'
updated_date: '2026-07-23 12:31'
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
- [ ] #1 CLI のディレクトリ解決が GUI と同じサポート形式優先ロジックを使用する
- [ ] #2 サポート形式と非サポート形式が混在するディレクトリでの --check テストが存在する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-115(BefoldKit への共通ロジック移設)で解消する方針。
<!-- SECTION:NOTES:END -->
