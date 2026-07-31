---
id: TASK-227
title: Quick Open の Enter/Tab 経路（commitSelection / completePath）を非同期化する
status: To Do
assignee: []
created_date: '2026-07-31 09:14'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 340000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppQuickOpenEnvironment.swift:96-102 の isDirectory / resolveFileToOpen が同期 FS アクセスのまま、QuickOpenModel.commitSelection（Enter、SupportedFileResolver 経由でディレクトリ列挙）と completePath（Tab、stat）から MainActor 上で呼ばれている。同ファイルの candidateSet / directoryEntries は task-205 で Task.detached 済み（「応答しないボリュームでは秒単位で止まる」とコメントあり）で、この 2 つだけ取り残されている。プロトコルの 2 メソッドを async 化し、呼び出し元は QuickOpenView のキーハンドラで Task に吸収する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Enter/Tab 押下時に MainActor 上でディレクトリ列挙・stat が実行されない
- [ ] #2 決定・補完の挙動（開くファイルの解決・パス補完結果）が従来と同等である
<!-- AC:END -->
