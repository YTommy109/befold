---
id: TASK-94.4
title: help の overview/サブコマンド説明/open の可視化を整理する
status: To Do
assignee: []
created_date: '2026-07-22 02:22'
labels: []
dependencies:
  - TASK-94.1
  - TASK-94.3
parent_task_id: TASK-94
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/BefoldRootCommand.swift の CommandConfiguration(30-50行)を以下の観点で整理する:
1. overview(abstract)が長い。「OVERVIEW: Mermaid/Markdown ビューア。」の後は USAGE のみで十分なので、discussion の内容を整理・簡潔化する。
2. bookmark/check の CommandConfiguration に abstract がなく、--help のサブコマンド一覧に説明が出ない。何をするサブコマンドか一目で分かる abstract を追加する。
3. open が実は defaultSubcommand であり、パス指定なしの起動時の既定挙動であることが --help から分からない(OpenPathsCommand は shouldDisplay: false で非表示)。open がデフォルト挙動であることを discussion 等で明示する。
4. open のオプション(--hidden-files 等)がサブコマンド(open)側にぶら下がっており、`befold open --help` を実行しないと見えない。これらはパス省略時の既定動作のオプションなので、トップレベルの --help からも分かるようにする(swift-argument-parser での実現方法を調査し、実装方針を決定する)。

TASK-94.1(--version)・TASK-94.3(言語方針)の結果を踏まえて最終的な文言・構成を決定すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold --help の OVERVIEW が簡潔になり、詳細説明は USAGE 以降に整理されている
- [ ] #2 befold --help のサブコマンド一覧で bookmark/check それぞれが何をするか一目で分かる説明が表示される
- [ ] #3 befold --help から、パス省略時(オプションのみ指定時含む)の既定動作が open サブコマンドであることが分かる
- [ ] #4 befold --help から open 相当のオプション(--hidden-files 等)の存在が分かる、または befold <path> --help 相当で確認できることが明記されている
- [ ] #5 BefoldRootCommandTests 等の既存 CLI テストが引き続き成功し、変更箇所のテストが追加されている
<!-- AC:END -->
