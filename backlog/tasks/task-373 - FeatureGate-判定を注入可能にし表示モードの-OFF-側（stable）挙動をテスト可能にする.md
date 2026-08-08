---
id: TASK-373
title: FeatureGate 判定を注入可能にし表示モードの OFF 側（stable）挙動をテスト可能にする
status: To Do
assignee: []
created_date: '2026-08-08 11:23'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/DisplayModeStore.swift
  - BefoldApp/befold/App/ViewerToolbarController.swift
  - BefoldApp/befold/Viewer/ViewerCapabilities.swift
  - docs/adr/0002-presentation-state-and-capabilities.md
priority: medium
type: bug
ordinal: 513000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘 3 件の統合（同型のゲート直読み・ゲート漏れのため構造で塞ぐ）。.claude/CLAUDE.md のゲート注入方針（ModeSegments.modes(isSourceDiffEnabled:) / MainMenuBuilder.addDisplayModeItems の形）に合わせる。

1. DisplayModeStore.restoredDisplayMode が FeatureGate.isSourceDiffEnabled を直読みしており、gate OFF（stable）での .diff→.source 降格がユニットテスト不能。DisplayModeStoreTests.demotesDiffWhenFeatureUnavailable は期待値を `FeatureGate.isSourceDiffEnabled ? .diff : .source` でヘッジしており、dev テストビルドでは OFF 分岐を一度も通らない。
2. ViewerToolbarController の diff-layout ツールバーエントリと ModeSegments.all が gate 値を static に焼き込んでおり、stable の構成（2 セグメント・diffLayout 無し）を検証できない。ViewerWindowControllerToolbarTests も identifier 一覧と segmentCount を live gate 値で条件分岐しており、OFF 側のアサーションは dev テストビルドでは絶対に失敗しない式になっている。
3. ViewerCapabilities.canSelectDiffMode に gate 判定が無い（PLAUSIBLE 判定）。ADR 0002 は setDisplayMode の executor ガードを「非検証経路が到達するため単独で成立すべき」としているが、gate OFF ビルドで .diff への遷移がこのガードを通過する。現状は gated UI が存在しないことだけが防波堤で、restoredDisplayMode の gate チェックは復元経路しか守らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 restoredDisplayMode がゲート値を引数で受け、ON/OFF 両方向の降格挙動がユニットテストで検証される
- [ ] #2 gate OFF 相当のツールバー構成（2 セグメント・diffLayout 項目無し）が live gate 値に依存しないユニットテストで検証される
- [ ] #3 canSelectDiffMode（または setDisplayMode の executor ガード）が gate OFF で .diff を拒否し、ユニットテストで担保される
<!-- AC:END -->
