---
id: TASK-96
title: '`befold check --help` / `befold bookmark --help` がヘルプを出さずエラーになる'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:37'
updated_date: '2026-07-22 13:57'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/BefoldRootCommand.swift
priority: high
type: bug
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出、ビルド済みバイナリで再現確認済み。BefoldRootCommand.swift の passthrough サブコマンドは `.captureForPassthrough` が `--help` をパス引数として飲み込むため、`befold check --help` は「No such path: --help」(exit 1)、`befold bookmark --help` は usage エラー(exit 64)になる。TASK-94.4 のルートヘルプ刷新で check サブコマンドと per-subcommand help を案内するようになったため、この行き止まりの遭遇率が上がっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `befold check --help` がヘルプテキストを表示し exit 0 で終了する
- [x] #2 `befold bookmark --help` がヘルプテキストを表示し exit 0 で終了する
- [x] #3 回帰テストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BookmarkPassthroughCommand/CheckPassthroughCommand の run() で --help/-h を検知したらヘルプテキストを出力する 2. CLICheckCommand/CLIBookmarkCommand にヘルプ文字列定数を持たせる 3. 回帰テストを追加する
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLICheckCommand/CLIBookmarkCommand に helpMessage 定数と --help/-h 検知を追加。befold check --help / befold bookmark --help が OVERVIEW/USAGE を含むヘルプテキストを exit 0 で出力する。回帰テスト4件追加。
<!-- SECTION:FINAL_SUMMARY:END -->
