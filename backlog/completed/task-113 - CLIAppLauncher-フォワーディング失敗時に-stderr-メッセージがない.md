---
id: TASK-113
title: 'CLIAppLauncher: フォワーディング失敗時に stderr メッセージがない'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 12:19'
updated_date: '2026-07-23 16:55'
labels:
  - bug
  - cli
dependencies: []
priority: medium
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
旧コードでは実行中インスタンスへのフォワーディング失敗時に stderr に診断メッセージを出力していたが、新コードは exit code 1 のみで無言終了する。ユーザーが原因を特定できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォワーディング失敗時に stderr に診断メッセージが出力される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstanceRouter.forward が false を返した箇所(既存インスタンスへの直接forward、起動後forward)の両方で stderr に診断メッセージを出力するよう CLIAppLauncher.run() を修正\n2. forwardOrReportFailure ヘルパーに集約し、旧実装(AppDelegate 時代)のメッセージ 'Failed to forward to the running instance.' を復元\n3. captureStderr ヘルパーで stderr 出力を検証するテストを2箇所分(既存インスタンスへの forward 失敗・起動後forward失敗)追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIAppLauncher.swift に forwardOrReportFailure(private) を追加し、既存インスタンスへの直接forward・起動後forwardの両呼び出し箇所を共通化。forward失敗時に 'Failed to forward to the running instance.\n' を stderr へ書き込むようにした(旧AppDelegate実装のメッセージを踏襲)。CLIAppLauncherTests に captureStderr ヘルパー(パイプを別スレッドで並行ドレインし body 実行中のブロックを回避)を追加し、forwardFailureWritesStderrMessage / launchAndForwardFailureWritesStderrMessage の2テストで両呼び出し経路の stderr 出力を検証。post-edit hook のビルド/テストがエラーなく完了。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
既存インスタンスへの forward が失敗した際に無言で exit code 1 になる問題を修正。CLIAppLauncher.swift に forwardOrReportFailure ヘルパーを追加し、forward失敗時に 'Failed to forward to the running instance.' を stderr に出力するようにした(旧 AppDelegate 実装で存在していたメッセージを復元)。既存インスタンス直接forward・起動後forwardの両経路に適用。CLIAppLauncherTests に stderr キャプチャヘルパーを用いた2テストを追加して検証。post-edit hook の swift build/swift test --skip Integration --skip FileWatcherTests がエラーなく完了。
<!-- SECTION:FINAL_SUMMARY:END -->
