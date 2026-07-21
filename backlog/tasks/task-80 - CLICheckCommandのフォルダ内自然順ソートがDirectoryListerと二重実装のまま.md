---
id: TASK-80
title: CLICheckCommandのフォルダ内自然順ソートがDirectoryListerと二重実装のまま
status: To Do
assignee: []
created_date: '2026-07-21 00:53'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-73.12でCLICheckCommand.resolveFileInDirectoryのソートをDirectoryLister.sortedByFileNameと同じlocalizedStandardCompareへ揃えたが、DirectoryLister側のfileReaderが注入不可(private static let fileReader = DefaultFileReader())なため、比較ロジック自体は依然として2箇所に手動で同期されたコピーとして存在する。task-73.12はこの2箇所が一度乖離したことが原因で発生したバグであり、将来どちらか一方だけ変更されれば同じ不整合が再発しうる。DirectoryLister側を fileReader 注入可能にし、CLICheckCommand から実装を再利用できるようにする(task-73.12の受け入れ基準に『可能であれば』として残されていた対応)。参照: code review finding, BefoldApp/befold/App/CLISubcommandCommand.swift:73, BefoldApp/befold/Viewer/DirectoryLister.swift
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLICheckCommandのフォルダ内ファイル解決ロジックがDirectoryListerの実装を再利用し、自然順ソートの比較ロジックが1箇所に集約されること
- [ ] #2 既存のCLICheckCommandTests・DirectoryListerのテストが全てパスすること
<!-- AC:END -->
