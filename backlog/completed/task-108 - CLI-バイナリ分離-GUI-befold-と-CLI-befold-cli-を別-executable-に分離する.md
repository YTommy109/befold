---
id: TASK-108
title: 'CLI バイナリ分離: GUI (befold) と CLI (befold-cli) を別 executable に分離する'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 09:17'
updated_date: '2026-07-23 10:20'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
priority: high
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI と GUI が共有している単一バイナリ befold を、GUI アプリ (befold) と CLI ツール (befold-cli) の 2 つの executable に分離する。CLI は befold.app/Contents/MacOS/befold-cli に同梱し、/usr/local/bin/befold の symlink 先を変更する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold-cli executable が Package.swift に定義され swift build でビルドできる
- [x] #2 befold-cli は NSApplication.run() を一切呼ばず、GUI 化しない
- [x] #3 befold (GUI) の AppDelegate から CLI 分岐ロジックが除去されている
- [x] #4 CLIInstaller の symlink 先が Contents/MacOS/befold-cli に変更されている
- [ ] #5 CLIShimInspector が旧 shim を staleSymlink と判定し再インストールを案内する
- [ ] #6 既存の CLI 統合テスト・ユニットテストが新構成で通る
- [ ] #7 新規テスト (CLIInstanceRouter 送信側、CLIAppLauncher、befold-cli 統合テスト) が追加されている
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
全 6 サブタスクを完了。BefoldCLI ライブラリ新設、befold-cli executable 新設、AppDelegate CLI 分岐除去、shim 移行対応、befoldCLITests 新設 (14 テスト)、統合テスト更新 (6 テスト)。573 テスト全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
