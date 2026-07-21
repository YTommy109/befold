---
id: TASK-73.10
title: ハイフンで始まるファイル名がCLIで不明なオプション扱いされ開けない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-21 00:22'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/CLIArgumentParser.swift:133-134'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIArgumentParser.parseOpenPaths は `-` で始まる引数を既知のフラグと照合したのち、それ以外は無条件に「不明なオプションです」エラーとして扱う。`--` のようなエスケープ手段が実装されていないため、例えば "-notes.md" のようなハイフンから始まる実在ファイル名をCLIから開くことができない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `--` 以降の引数を常にパスとして扱うなど、ハイフンで始まる正当なパスをCLI経由で開ける手段を提供する
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
swift-argument-parserへの移行(task-76)の一部として、-- ターミネータでハイフン始まりのパスをオプションと解釈せず開けるようにする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
task-76(swift-argument-parserへの移行)で解決。OpenPathsCommandの@Argument var pathsはswift-argument-parser標準の-- ターミネータに対応しており、befold -- -notes.md のように -- 以降を常にパスとして扱える(BefoldRootCommandTests.dashDashEscapesHyphenPrefixedPathsで検証)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
swift-argument-parser移行(task-76)により標準の-- ターミネータが使えるようになり、ハイフンで始まる実在パスも befold -- -notes.md のように開けるようになった。
<!-- SECTION:FINAL_SUMMARY:END -->
