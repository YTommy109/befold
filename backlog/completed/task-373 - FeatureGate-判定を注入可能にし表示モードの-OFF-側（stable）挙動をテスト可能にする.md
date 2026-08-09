---
id: TASK-373
title: FeatureGate 判定を注入可能にし表示モードの OFF 側（stable）挙動をテスト可能にする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 11:23'
updated_date: '2026-08-08 12:44'
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
- [x] #1 restoredDisplayMode がゲート値を引数で受け、ON/OFF 両方向の降格挙動がユニットテストで検証される
- [x] #2 gate OFF 相当のツールバー構成（2 セグメント・diffLayout 項目無し）が live gate 値に依存しないユニットテストで検証される
- [x] #3 canSelectDiffMode（または setDisplayMode の executor ガード）が gate OFF で .diff を拒否し、ユニットテストで担保される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ゲート値を注入する形へ変更。(1) DisplayModeStore は init(defaults:isSourceDiffEnabled:) で受け取り FeatureGate 直読みを廃止（本番値は PerFileStateStore が注入）。デフォルト引数は置かず必須引数にした。(2) ViewerToolbarController.layout を layout(isSourceDiffEnabled:) へ切り出し、live 用は static let で 1 度だけ解決。テスト入口として defaultItemIdentifiers(isSourceDiffEnabled:) を追加。(3) ViewerCapabilities.init に必須引数 isSourceDiffEnabled を追加し canSelectDiffMode / canToggleDiffLayout をゲートで拒否（ViewerWindowController.capabilities が FeatureGate を渡す）。FeatureGate の露出点コメントも DisplayModeStore → PerFileStateStore / ViewerWindowController.capabilities へ更新（FeatureGateEnumerationTests が突き合わせる）。検証: swift test --skip Integration --skip FileWatcherTests で 1120 tests / 155 suites すべて成功。swiftlint（プラグイン同梱バイナリ）で変更ファイルの警告 0 件。

AC#3 差し戻し: ViewerCapabilities へのゲート追加を撤回した。.diff が setDisplayMode / mirrorDisplayMode に届く経路を全数確認（ViewerWindowController.swift:686 / :730 の呼び出し元）した結果、UI 2 経路（ModeSegments.all・MainMenuBuilder.addDisplayModeItems）と保存値の復元 1 経路のみで、cmd+U の戻り先は effectiveDisplayMode 由来、他ウィンドウのミラーは同一ビルド、CLI は ViewerWindowManager.swift:207 のとおり .source/.rendered しか渡さない。UI 以外の唯一の経路は DisplayModeStore の復元であり、そこは AC#1 で塞がっている。能力側のゲートは到達不能な状態への三重目のガードで、ゲート読み出し箇所が 3 箇所に増え、『能力は提示状態から導出する』(ADR 0002 段 2) にビルドフラグが混ざる分だけ負債になる。元のレビュー指摘も PLAUSIBLE 判定だった。判断の根拠は DisplayModeStore の doc コメントに残した。検証: swift test で 1119 tests / 155 suites 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示モードの差分ゲートのうち、DisplayModeStore の降格（UI 以外の唯一の経路）とツールバー構成を注入可能にし、ON/OFF 両分岐をパラメータ化テストで検証。live gate 値に依存したヘッジ式のアサーションを撤去した。ViewerCapabilities へのゲート追加（当初の AC#3）は、.diff の到達経路を全数確認した結果、到達不能な状態への三重目のガードだったため実施せず、判断の根拠を DisplayModeStore の doc コメントへ記録した。swift test 1119 件成功、変更ファイルの swiftlint 警告 0。
<!-- SECTION:FINAL_SUMMARY:END -->
