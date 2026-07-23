---
id: TASK-108.6
title: 既存テストの更新と befold-cli 統合テスト追加
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-23 09:18'
updated_date: '2026-07-23 10:14'
labels: []
dependencies:
  - TASK-108.3
  - TASK-108.5
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
parent_task_id: TASK-108
priority: high
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldRootCommandIntegrationTests の builtExecutableURL() を befold-cli バイナリパスに更新する。BefoldRootCommandTests の import 先を BefoldCLI モジュールに変更する。befold-cli の統合テスト（--check, --version, --help の出力と exit code）を befoldTests に追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldRootCommandIntegrationTests が befold-cli バイナリを正しく解決してテストが通る
- [ ] #2 BefoldRootCommandTests の import が BefoldCLI に変更されテストが通る
- [ ] #3 befold-cli の統合テスト (--check, --version, --help) が追加されている
- [ ] #4 統合テストが exit code を検証している
- [ ] #5 swift test で全テストが通る
<!-- AC:END -->
