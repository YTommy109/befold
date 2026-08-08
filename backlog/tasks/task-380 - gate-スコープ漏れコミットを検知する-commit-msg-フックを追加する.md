---
id: TASK-380
title: (gate) スコープ漏れコミットを検知する commit-msg フックを追加する
status: To Do
assignee: []
created_date: '2026-08-08 11:49'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 640000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。(gate) スコープ規約は .claude/CLAUDE.md に明文化済み（過去に grep 見逃しで stable リリースノートへ混入した実例も記載済み）だが、dacb72e で再び漏れた（TASK-375）。明文化は 2 回目の対処として数えない、の原則どおり機械的に強制する。

内容: commit-msg（または pre-commit）フックで、ステージされた差分が FeatureGate 配下のコード（`FeatureGate` への参照を含む行の追加・変更、および FeatureGate.swift 由来の別名ゲート computed property の参照）に触れているのに件名に `(gate)` スコープが無い場合に警告またはブロックする。混在コミット（ゲート内外を両方触る）の扱い方針もフックのメッセージで案内する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FeatureGate 関連の差分を含み件名に (gate) が無いコミットがフックで検知される
- [ ] #2 ゲートに触れないコミットは影響を受けない
- [ ] #3 フックの導入方法（配置場所・有効化手順）がリポジトリ内に文書化されている
<!-- AC:END -->
