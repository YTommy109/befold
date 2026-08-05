---
id: TASK-319
title: DiffDisplayPreference がウィンドウごとに別インスタンスになり表示状態が同期しない問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:07'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 503000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

DiffDisplayPreference はアプリ全体で共有する設計（doc コメントにも「同じファイルを 2 窓で開いたときの不整合を防ぐ」旨の記載）だが、ViewerWindowManager.openViewer（ViewerWindowManager.swift:233-252）は ViewerWindowController の init へ diffDisplayPreference を渡しておらず、デフォルト引数（ViewerWindowController.swift:147 の DiffDisplayPreference()）がウィンドウごとに別インスタンスを生成している。対照的に sidebarDisplayPreference は同じ init 呼び出しで manager の共有インスタンスが明示的に渡されている。

症状: 同じ変更ありファイルを 2 窓で開き、片方で「変更を表示」（Cmd+Ctrl+J）をトグルしてももう片方に反映されない。各窓で独立にトグルすると UserDefaults への永続化が last-write-wins になり、次回起動時に復元される状態が不定になる。

修正: ViewerWindowManager に共有インスタンスを持たせ、openViewer で明示的に渡す（sidebarDisplayPreference と同じ形）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 2 窓で同じファイルを開いた状態で片方の差分表示トグルを切り替えると、もう片方にも反映される
- [ ] #2 差分表示状態の永続化・復元が窓の数によらず一意に定まる
- [ ] #3 共有インスタンスが渡ることを検証するテストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
