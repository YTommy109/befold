---
id: TASK-120
title: 矛盾するペアフラグ(--line-numbers/--no-line-numbers 等)を排他指定にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-24 04:39'
updated_date: '2026-07-24 04:51'
labels:
  - cli
  - refactor
dependencies: []
priority: medium
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OpenCLIOptions では --hidden-files/--no-hidden-files、--line-numbers/--no-line-numbers、--source/--preview を 2 つの独立した @Flag で定義し、両方指定を validate() の実行時エラーで弾いている。ArgumentParser の @Flag(inversion: .prefixedNo) など標準の排他指定手段を使い、両立しないフラグを構造的に同時指定できない形へ見直す。3 ペアすべてを対象とし、既存の CLIOpenOptions への変換(nil=未指定を保つ 3 値)を維持する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 矛盾するフラグのペアが構造的に同時指定できない、もしくはパーサ標準の仕組みで排他が保証される
- [x] #2 未指定時は nil(保存済み設定維持)を保つ 3 値の意味論が維持される
- [x] #3 既存のオプション名(--line-numbers/--no-line-numbers 等)との後方互換が保たれる
- [x] #4 3 ペア(hidden-files / line-numbers / source-preview)すべてに適用される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 3ペア(hidden-files/no-hidden-files, line-numbers/no-line-numbers, source/preview)を EnumerableFlag 準拠の enum で再定義し、@Flag var x: Enum? として単一値で受ける。ArgumentParser 標準の仕組みで同時指定がパースエラーになる(構造的排他)
2. name(for:)/help(for:) でカスタム名(既存オプション名)とヘルプ文言を保持し後方互換を維持
3. nil=未指定の3値意味論を維持(.map { $0 == .on } で CLIOpenOptions へ変換)
4. validate() の手動排他チェックを削除
5. 失敗テスト: 3ペアすべてで同時指定がエラーになることを確認 → 実装 → swift test
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3ペア(hidden-files/no-hidden-files, line-numbers/no-line-numbers, source/preview)を EnumerableFlag 準拠の enum + 単一値 @Flag(Enum?) で再実装。ArgumentParser 標準の仕組みで同時指定がパース段階でエラーになり構造的排他を実現。name(for:)/help(for:) で既存オプション名とヘルプを保持(後方互換)、.map { $0 == .on } で nil=未指定の3値意味論を維持。手動 validate() 排他チェックを削除。BefoldCLICommandTests で3ペアの同時指定エラー・個別解釈を swift test で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
