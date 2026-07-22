---
id: TASK-94
title: CLI --help の内容を整理・改善する
status: To Do
assignee: []
created_date: '2026-07-22 02:21'
updated_date: '2026-07-22 11:42'
labels: []
dependencies: []
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状の `befold --help` (BefoldApp/befold/App/BefoldRootCommand.swift) には複数の分かりにくさがある。子タスクで個別に対応する:
1. overview 短縮
2. subcommand 説明の明示
3. open がデフォルトサブコマンドであることの明示
4. --version の実装
5. デフォルトで最前面ウィンドウに開く挙動への変更(オプションで新規ウィンドウ切替)
6. help 文言の言語方針統一(OS/ロケール追従)

対象ファイル: BefoldApp/befold/App/BefoldRootCommand.swift
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-94.2(デフォルトウィンドウ挙動変更)はユーザー判断により対応不要とし Done でクローズ。CLIからの起動は単一/複数パスとも現行通り常に新規ウィンドウのまま。
<!-- SECTION:NOTES:END -->
