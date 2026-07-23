---
id: TASK-106
title: CLI経由でファイルを開いた後にプロセスが終了しない
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-23 06:37'
updated_date: '2026-07-23 06:51'
labels: []
dependencies:
  - TASK-105
priority: medium
type: bug
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold file.mmd を実行すると、ファイルは開かれるがCLIプロセスが終了しない。open コマンドのようにファイルを開いたら即座に終了することが期待される。

原因: 既存インスタンスがある場合は転送後に exit(0) で終了するが、既存インスタンスがない場合は AppDelegate.launch() の .launchAsNewInstance 分岐で NSApplication.shared.run() がメインループに入り、CLIプロセスがそのままGUIアプリになる。

TASK-105（相対パス問題）が先に修正される必要がある。パスが正しく解決されれば既存インスタンスへの転送が成功し exit(0) で終了するケースが増えるが、初回起動時（既存インスタンスなし）の問題は残る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold file.mmd 実行後、ファイルが開かれたらCLIプロセスが終了する（open コマンド相当の振る舞い）
- [ ] #2 既存インスタンスがない場合でもCLIは終了し、アプリは別プロセスとして起動する
- [ ] #3 befold（パス引数なし）の既存動作に影響がない
<!-- AC:END -->
