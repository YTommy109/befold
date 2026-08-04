---
id: TASK-94.3
title: CLI help/メッセージの言語をOS/ロケール設定に追従させる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 02:21'
updated_date: '2026-07-22 12:05'
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
- [x] #1 CLI(befold --help/open --help/bookmark/check)の abstract・usage・discussion・引数help・エラーメッセージが全て英語に統一されている
- [x] #2 既存の CLIBookmarkCommand/CLICheckCommand のテストが更新後の英語メッセージで引き続き成功する
- [x] #3 BefoldKit側の RejectReason 等、GUI と共有する既存のローカライズ済み文言(日本語/英語)には変更を加えない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (当初案) String(localized:bundle:)+Localizable.xcstringsで日英自動切替を実装しようとしたが、TDDのRED確認中に判明: SPMの swift test プロセス内では Bundle.l10n.localizations が ["en"] しか報告せず、既存キー(cli.folder.noFile等)ですら実行時解決できずキーそのものが漏れる(swift run では動く一方、swift test 環境固有の問題)。既存のLocalizationTests.swiftも実行時解決は検証しておらずカタログの静的完全性のみを見ている前例に合致。
2. ユーザーに報告し方針転換: help/エラーメッセージは英語のみに統一する(日本語ローカライズ機構は導入しない)。
3. BefoldRootCommand.swift の abstract/usage/discussion/@Argument・@Flag・@Optionのhelp文言/validate()のエラー3件を全て英語化。
4. CLISubcommandCommand.swift の CLIBookmarkCommand/CLICheckCommand の全メッセージを英語化。
5. 既存テスト(CLICheckCommandTests.swift)の日本語文言アサーションを英語に更新。
6. BefoldKit側のRejectReason等、GUIと共有する既存ローカライズ(日本語/英語)には手を加えない(スコープ外)。
7. swift test 全体で回帰がないことを確認。swift run befold --help 等で実際の出力が英語になっていることを手動確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。BefoldRootCommand.swift(abstract/usage/discussion/help/エラー文言)とCLISubcommandCommand.swift(CLIBookmarkCommand/CLICheckCommandの全メッセージ)を英語に統一。swift test --skip Integration --skip FileWatcherTests で全559件成功。swift run befold --help / open --help / bookmark --help / check --help の実行結果を手動確認し、すべて英語表示になっていることを確認した(bookmark/checkの--helpがcaptureForPassthroughにより機能しない点は既存の挙動でTASK-94.4のスコープ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI(befold --help/open --help/bookmark/check の abstract・usage・discussion・引数help・エラーメッセージ・実行結果メッセージ)を全て英語に統一した。当初はLocalizable.xcstringsを使ったOS/ロケール自動切替を試みたが、TDDのRED確認でswift testプロセス内ではBundle.l10nのローカライズ解決が機能しない(既存キーでも同様)ことが判明し、ユーザーと相談の上「英語のみ」に方針転換した。BefoldKit側の既存ローカライズ(RejectReason等)には手を加えていない。CLICheckCommandTestsの日本語文言アサーションも英語に更新し、swift test(559件)全て成功。swift runでの実機出力も確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
