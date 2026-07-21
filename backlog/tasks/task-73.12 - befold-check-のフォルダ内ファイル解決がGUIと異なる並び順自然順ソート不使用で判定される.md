---
id: TASK-73.12
title: befold check のフォルダ内ファイル解決がGUIと異なる並び順(自然順ソート不使用)で判定される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-21 00:35'
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
- [x] #1 CLICheckCommand のフォルダ解決ロジックが DirectoryLister と同じ並び順・優先順位で判定すること(可能であれば DirectoryLister 側を注入可能にして再利用する)
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
CLICheckCommand.resolveFileInDirectoryのソート比較を.path文字列のバイト列比較からlocalizedStandardCompare(自然順ソート)へ変更し、DirectoryLister.sortedByFileNameと同じ並び順にする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLICheckCommand.resolveFileInDirectoryのソートを/bin/zsh.path < .path(バイト列比較)からlastPathComponent.localizedStandardCompareによる自然順ソートへ変更し、DirectoryLister.sortedByFileNameと同じ並び順・優先順位(対応形式優先→先頭ファイル)にした。DirectoryLister自体はDefaultFileReaderに固定されテスト注入できないため、AC冒頭の『可能であれば』の代替として比較ロジックのみ揃える形にした(fileReader注入によるテスト容易性は維持)。CLICheckCommandTests.swiftに"file10.md"/"file2.md"混在フォルダーでの再現テストを追加し、DirectoryLister.firstSupportedFileの結果と一致することも検証。swift test 528件全パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLICheckCommand.resolveFileInDirectoryのソートをバイト列比較からlocalizedStandardCompareによる自然順ソートへ変更し、DirectoryListerと同じ並び順にした。file2.md/file10.mdのような番号付きファイルでbefold checkとGUIの判定結果が食い違う不一致を解消した。
<!-- SECTION:FINAL_SUMMARY:END -->
