---
id: TASK-456
title: CLI ロジックを befold-cli から BefoldCLI へ移し、befoldCLITests を Xcode 経路にも載せる
status: To Do
assignee: []
created_date: '2026-08-11 23:28'
labels:
  - ci
dependencies: []
priority: low
type: chore
ordinal: 680000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-439 で確定した残差。

`befoldCLITests` の 14 suites / 72 tests は `swift test` でのみ実行され、`xcodebuild test` では実行されない。8 ファイルが `@testable import befold_cli` で**実行ファイルターゲット**の中身に触るため Xcode ではテストホストが必要だが、**Xcode は plain tool を TEST_HOST として受け付けない**（実測: project.yml へ `TEST_HOST: \$(BUILT_PRODUCTS_DIR)/befold-cli` を書くと、バイナリが実在していても `Could not find test host for befoldCLITests` でスキーム構築の時点で落ちる。スキームのビルド対象に befold-cli を追加しても同じ）。

載せるには、`CLIAppLauncher` / `BefoldCLICommand` / `CLIBookmarkRouter` / `ProcessLaunching` / `AckWaiting` などの CLI ロジックを `befold-cli`（executable）から `BefoldCLI`（framework）へ移し、実行ファイル側を薄い main だけにする構造変更が要る。

現状のずれは project.yml のコメントと `PackageProjectTargetParityTests` の `packageOnlyTargets` に明記してあり、黙って壊れることはない。CI は `swift test` のみを実行するため、CI で走るテスト集合には影響しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI ロジックが BefoldCLI へ移り、befold-cli は薄い main のみになっている
- [ ] #2 project.yml に befoldCLITests ターゲットがあり、xcodebuild test で実行される
- [ ] #3 PackageProjectTargetParityTests の packageOnlyTargets が空になっている
- [ ] #4 swift test と xcodebuild test のテスト件数が一致する
<!-- AC:END -->
