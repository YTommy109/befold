---
id: TASK-80
title: CLICheckCommandのフォルダ内自然順ソートがDirectoryListerと二重実装のまま
status: Done
assignee: []
created_date: '2026-07-21 00:53'
updated_date: '2026-07-21 01:57'
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
- [x] #1 CLICheckCommandのフォルダ内ファイル解決ロジックがDirectoryListerの実装を再利用し、自然順ソートの比較ロジックが1箇所に集約されること
- [x] #2 既存のCLICheckCommandTests・DirectoryListerのテストが全てパスすること
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化を検討: CLICheckCommand.resolveFileInDirectory を独自実装のまま fileReader だけ揃える案もあったが、根本原因(2箇所の手動同期)を解消するため DirectoryLister 側の関連関数(listFiles/firstSupportedFile/resolveFileToOpen/内部の sortedContents)に fileReader パラメータ(デフォルト値は既存の private static fileReader)を追加し、CLICheckCommand.resolveFileInDirectory を削除して DirectoryLister.resolveFileToOpen(at:fileReader:) への一行委譲に置き換えた。副次効果として、sortedContents のファイル分類が resourceValues(.isDirectoryKey) ベースから fileReader.isDirectory/isExistingFile ベースに変わり、CLICheckCommand 側が採用していたより厳密な『実在ファイルのみ』判定に統一された。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLICheckCommand.resolveFileInDirectory の自然順ソート二重実装を解消。DirectoryLister の fileReader を関数引数として注入可能にし(listFiles/firstSupportedFile/resolveFileToOpen/sortedContents)、CLICheckCommand は自前実装を削除して DirectoryLister.resolveFileToOpen(at:fileReader:) を再利用するようにした。DirectoryListerTests に fileReader 注入を検証する回帰テストを追加。swift test --skip Integration --skip FileWatcherTests で537件全てパス(既存のCLICheckCommandTests・DirectoryListerTestsも含む)。
<!-- SECTION:FINAL_SUMMARY:END -->
