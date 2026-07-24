---
id: TASK-120
title: 矛盾するペアフラグ(--line-numbers/--no-line-numbers 等)を排他指定にする
status: To Do
assignee: []
created_date: '2026-07-24 04:39'
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
- [ ] #1 矛盾するフラグのペアが構造的に同時指定できない、もしくはパーサ標準の仕組みで排他が保証される
- [ ] #2 未指定時は nil(保存済み設定維持)を保つ 3 値の意味論が維持される
- [ ] #3 既存のオプション名(--line-numbers/--no-line-numbers 等)との後方互換が保たれる
- [ ] #4 3 ペア(hidden-files / line-numbers / source-preview)すべてに適用される
<!-- AC:END -->
