---
id: TASK-133
title: ArgumentParser 依存を CLI 実行ファイルへ隔離し BefoldCLI/GUI の層違反を解消する
status: To Do
assignee: []
created_date: '2026-07-24 22:40'
updated_date: '2026-07-25 00:25'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: high
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldCLI/CLIOpenOptions.swift が import ArgumentParser し、OpenCLIOptions(ParsableArguments)・4 つの EnumerableFlag 実装・CLISortOrderOption の ExpressibleByArgument 適合を抱えるが、これらは befold-cli/BefoldCLICommand.swift の 1 箇所からしか使われない。共有ライブラリ BefoldCLI に CLI 専用のパース層が同居するため、GUI ターゲット befold も import BefoldCLI 経由で ArgumentParser を推移的にリンクし、さらに Package.swift/project.yml で GUI が ArgumentParser を直接依存しているが GUI コードは ArgumentParser を一切使っていない(dead dependency)。dagayn の SAP 指摘(BefoldCLI distance=1.0, pain zone)の一因。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OpenCLIOptions と 4 つの *Flag enum・CLISortOrderOption の ExpressibleByArgument 適合が befold-cli ターゲットへ移動している
- [ ] #2 CLIOpenOptions(素の Codable 構造体)と CLISortOrderOption 本体は BefoldCLI に残り、BefoldCLI から import ArgumentParser が消えている
- [ ] #3 GUI(befold)と BefoldCLI の ArgumentParser 直接依存が Package.swift / project.yml から除去され、swift build・swift test・xcodebuild が通る
- [ ] #4 CLI の --help / 各フラグ挙動に回帰がない(既存 CLI テストが通る)
<!-- AC:END -->
