---
id: TASK-381
title: 規約文書が引用するコードシンボルの実在チェックを追加する
status: To Do
assignee: []
created_date: '2026-08-08 11:50'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 641000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) の振り返りから。.claude/CLAUDE.md が模範例として引用した `BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:)` は、同ブランチの先行コミットで削除済みの関数だった（TASK-374）。文書がコードを名指しする限り同型の陳腐化は再発するため、引用シンボルの実在を機械的に検査する。

内容: .claude/CLAUDE.md（必要なら docs/ の ADR も対象に含めるか判断）内のバッククォート引用からシンボル名（関数・プロパティ・型名）を抽出し、リポジトリ内に宣言が存在するかを rg で確認するスクリプトを scripts/ に置き、CI または pre-commit で実行する。誤検知（コマンド名・ファイルパス・一般語）の除外方法を含めて設計する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TASK-374 の型（削除済みシンボルを引用し続ける文書）がチェックで検知される
- [ ] #2 誤検知の除外手段があり、既存文書に対してチェックがグリーンで通る
- [ ] #3 CI または pre-commit に組み込まれている
<!-- AC:END -->
