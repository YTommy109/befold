---
id: TASK-94.3
title: CLI help/メッセージの言語をOS/ロケール設定に追従させる
status: To Do
assignee: []
created_date: '2026-07-22 02:21'
labels: []
dependencies: []
parent_task_id: TASK-94
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 BefoldRootCommand.swift の abstract/usage/discussion/help 文言や CLICheckCommand・CLIBookmarkCommand 等のメッセージが日本語と英語混在になっている(例: エラーメッセージや一部識別子は英語、説明文は日本語)。
方針: macOS のロケール設定または環境変数(LANG 等)に応じて日本語/英語の help・エラーメッセージを切り替える(自動切替)。
BefoldKit には TASK-1.15 で導入したローカライズ基盤(RejectReason 等)があるため、それを流用・拡張できないか調査すること。
対象: BefoldApp/befold/App/BefoldRootCommand.swift の全 CommandConfiguration(abstract/usage/discussion)、@Argument/@Flag/@Option の help 文言、CLIBookmarkCommand/CLICheckCommand/CLICommandResultPrinter のメッセージ文言。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold --help の abstract/usage/discussion、各サブコマンドの help 文言、エラーメッセージが、ロケール設定(または LANG 等の環境変数)に応じて日本語/英語に切り替わる
- [ ] #2 既存のローカライズ基盤(BefoldKit)との重複実装がなく、一貫した仕組みで管理されている
- [ ] #3 l10n-check スキルや既存テストで翻訳漏れがないことを確認できる
<!-- AC:END -->
