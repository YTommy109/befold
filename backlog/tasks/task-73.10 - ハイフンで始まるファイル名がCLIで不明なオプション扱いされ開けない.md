---
id: TASK-73.10
title: ハイフンで始まるファイル名がCLIで不明なオプション扱いされ開けない
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
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
- [ ] #1 `--` 以降の引数を常にパスとして扱うなど、ハイフンで始まる正当なパスをCLI経由で開ける手段を提供する
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
