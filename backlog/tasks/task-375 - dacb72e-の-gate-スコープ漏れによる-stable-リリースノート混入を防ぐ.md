---
id: TASK-375
title: dacb72e の (gate) スコープ漏れによる stable リリースノート混入を防ぐ
status: To Do
assignee: []
created_date: '2026-08-08 11:23'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 636000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。コミット dacb72e「feat: 表示モード切替を3セグメント＋レイアウトトグルにして cmd+1〜4 を割り当てる」は FeatureGate 配下のコード（diff セグメント、cmd+3 項目、cmd+4 レイアウト項目、gated な復元時降格）を変更しているが、件名に (gate) スコープが無い。/release-notes stable はコミット件名だけで機械的に除外判定するため、このままでは stable ビルドに存在しない cmd+3（差分）/ cmd+4（レイアウト）のショートカットがリリースノートに載る。

対応の選択肢: (a) 未 push またはマージ前なら gated 部分を (gate) スコープ付きコミットに分割 or 件名を非 gated の cmd+1〜2 に絞ってリワード、(b) それが不可なら次回 stable の /release-notes 生成時に手動除外し、その旨を記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable 向けリリースノートに cmd+3（差分）/ cmd+4（レイアウト）の記載が混入しない
- [ ] #2 対応方法（コミット分割・リワード / リリースノート側での除外）を決めて実施した記録が残る
<!-- AC:END -->
