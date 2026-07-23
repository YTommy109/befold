---
id: TASK-108.5
title: befoldCLITests ターゲットの新設と新規ユニットテスト追加
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 09:18'
updated_date: '2026-07-23 10:14'
labels: []
dependencies:
  - TASK-108.2
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
parent_task_id: TASK-108
priority: high
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befoldCLITests テストターゲットを Package.swift に追加し、BefoldCLI ライブラリのユニットテストを実装する。CLIInstanceRouter 送信側の forward notification 発行・ACK 待機ロジック、CLIAppLauncher の open -a + poll + forward フロー（ProcessLaunching プロトコルでモック）をテストする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Package.swift に befoldCLITests テストターゲットが定義されている
- [ ] #2 CLIInstanceRouter 送信側のユニットテストが実装されている (forward の notification 発行・ACK 待機)
- [ ] #3 CLIAppLauncher のユニットテストが実装されている (ProcessLaunching プロトコルでモック)
- [ ] #4 swift test で befoldCLITests が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befoldCLITests ターゲット新設。CLIAppLauncher を run() メソッドに分離してテスト可能に。CLIAppLauncherTests (8テスト) + CLIInstanceRouterDecodeTests (6テスト) 実装。552テスト全パス。
<!-- SECTION:NOTES:END -->
