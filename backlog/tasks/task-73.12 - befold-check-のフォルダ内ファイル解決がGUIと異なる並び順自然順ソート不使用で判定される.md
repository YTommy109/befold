---
id: TASK-73.12
title: befold check のフォルダ内ファイル解決がGUIと異なる並び順(自然順ソート不使用)で判定される
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/CLISubcommandCommand.swift:67-73'
  - 'BefoldApp/befold/Viewer/DirectoryLister.swift:98-103'
parent_task_id: TASK-73
priority: low
type: bug
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLICheckCommand.resolveFileInDirectory は DirectoryLister の「フォルダから開くファイルを解決する」ロジックを再実装しているが、ソートに `.sorted { $0.path < $1.path }`(バイト列比較)を使っており、DirectoryLister が使う localizedStandardCompare による自然順ソートと異なる。"file2.md"と"file10.md"が混在するフォルダ等で、befold check <folder> が判定するファイルと、実際に befold <folder> がGUIで開くファイルが食い違う可能性がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLICheckCommand のフォルダ解決ロジックが DirectoryLister と同じ並び順・優先順位で判定すること(可能であれば DirectoryLister 側を注入可能にして再利用する)
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
