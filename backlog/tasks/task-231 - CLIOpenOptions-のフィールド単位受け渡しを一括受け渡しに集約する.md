---
id: TASK-231
title: CLIOpenOptions のフィールド単位受け渡しを一括受け渡しに集約する
status: To Do
assignee: []
created_date: '2026-07-31 09:15'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 380000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIOpenOptions の展開が AppDelegate.swift:230-238 / :275-281、SessionRestorer.swift:180-187 の 3 箇所でフィールド単位に手写しされ、ViewerWindowManager.swift:140-155 の受け側でも optional を個別展開している。フィールド追加時に 4 箇所の修正が必要で、忘れると「セッション復元経路だけ新オプションが効かない」という気付きにくい欠落になる。ViewerWindowManager の API を CLIOpenOptions 受け（openViewer(for:options:) / applyDisplayOverrides(_:)）に寄せ、options.sortOrder.map { _ in options.viewerSortOrder } という不自然な変換も解消する。オプションなし呼び出し向けに既定引数を用意する。既存の ViewerWindowManagerDisplayOverridesTests 等のシグネチャ変更に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLIOpenOptions のフィールド追加時に転送コードの修正箇所が 1 箇所になっている
- [ ] #2 CLI オープン・セッション復元・通常オープンの各経路でオプション適用が従来どおり動作しテストが通る
<!-- AC:END -->
