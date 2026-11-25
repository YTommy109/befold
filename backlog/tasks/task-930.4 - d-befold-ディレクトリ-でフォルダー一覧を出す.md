---
id: TASK-930.4
title: (d) befold <ディレクトリ> でフォルダー一覧を出す
status: To Do
assignee: []
created_date: '2026-11-25T00:12:58Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: feature
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 5。いまは befold <ディレクトリ> がフォルダー内の最初のファイルを開く（SupportedFileResolver.resolveFileToOpen 経由で DocumentOpener.openViewer へ渡す）。ディレクトリを指定した意図どおり、その一覧を出すようユーザーが決めた（2026-11-25）。Finder・Dock・最近使った項目からディレクトリを開く経路も同じ解決を通っているため、扱いを揃えるか個別に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold <ディレクトリ> で開いた窓は、本文にそのディレクトリの一覧を出し、ファイルを開かない
- [ ] #2 ファイルの無いディレクトリでも、cli.folder.noFile のアラートではなく一覧（空の状態）を出す
- [ ] #3 Finder・Dock・最近使った項目・リポジトリを開く経路でディレクトリを渡したときの扱いを決め、決めた内容を Notes に残す
- [ ] #4 befold --help など CLI の説明文と docs の記述を新しい挙動に合わせる
<!-- AC:END -->
