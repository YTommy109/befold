---
id: TASK-378
title: FeatureGate の直接参照を配線点以外で禁止する swiftlint custom rule を追加する
status: To Do
assignee: []
created_date: '2026-08-08 11:49'
labels: []
dependencies:
  - TASK-373
references:
  - BefoldApp/befold/App/FeatureGate.swift
priority: medium
type: chore
ordinal: 514000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。ゲート注入方針（ゲート値を引数で受ける純粋関数に切り出し OFF 側もテストする）は .claude/CLAUDE.md に明文化済みだったが、同じブランチで 3 箇所（DisplayModeStore.restoredDisplayMode / ViewerToolbarController の static 焼き込み / ViewerCapabilities.canSelectDiffMode のゲート漏れ、TASK-373）が違反した。「決めたことには、破れたら落ちるものを付ける」に従い、文書ではなく lint で強制する。

内容: `FeatureGate.` への直接参照を、FeatureGate.swift 自身と明示的に許可した配線点（composition root でゲート値を注入する箇所）以外で禁止する swiftlint custom rule（custom_rules の regex で足りるか、allowlist の持ち方を含めて設計する）。

前提: TASK-373 が直しきる前に導入すると既存違反で即赤になるため、TASK-373 完了後に導入する（依存に設定済み）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FeatureGate.swift と許可配線点以外での `FeatureGate.` 直接参照が swiftlint で検出される
- [ ] #2 main とのベースライン差分ゼロ（既存違反は TASK-373 側で解消済みか、明示的に allowlist される）
- [ ] #3 ルールの意図と allowlist への追加基準が .claude/CLAUDE.md に 1 段落で記載されている
<!-- AC:END -->
