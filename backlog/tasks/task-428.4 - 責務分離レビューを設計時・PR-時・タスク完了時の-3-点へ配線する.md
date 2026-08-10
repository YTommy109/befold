---
id: TASK-428.4
title: 責務分離レビューを設計時・PR 時・タスク完了時の 3 点へ配線する
status: To Do
assignee: []
created_date: '2026-08-10 12:34'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: medium
type: chore
ordinal: 104400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
行数の機械判定では責務の混在を捕まえられない。TASK-411 の +Capabilities / +Diff / +WindowHelpers が実例で、行数上限は回避されているのに責務は分離されていなかった。意味の判断を担うレビューを独立したレビュアーとして立て、3 点から回るよう配線する。

## レビュアーの新設

`.claude/agents/` に責務分離を見るサブエージェントを追加する。既存 5 体（accessibility-reviewer / backlog-hygiene-reviewer / performance-reviewer / security-reviewer / vendored-deps-auditor）と同じ作法に揃える（Read/Grep/Glob/Bash、修正はせず報告のみ）。

判断基準の一次情報源は `docs/dev/rules/product-code.md:123-137` の「責務分離」節。同じ内容をエージェント定義へ書き写さず参照させること（単一情報源）。少なくとも次を見る。

- 1 ファイル 1 主要型が保たれているか
- 複数の関心が 1 つの型に同居し始めていないか（規約の例: ウィンドウ管理 + サイドバー + 履歴）
- 追加された extension が責務単位の分割か、行数上限の回避か
- 親から子へのクロージャ注入が 3 つを超えていないか（超えたら delegate プロトコルを検討、という既存規定）
- プロトコル準拠の数が増えていないか（TASK-411 の ViewerWindowController は 5 プロトコルを兼ねていた）

## 3 点への配線

1. **設計時**: `.claude/skills/review-design.md` のチェックリストへ項目を追加する。「この変更で触る型グループの現行行数と、追加後の見積もり」「責務（プロトコル準拠・注入クロージャ・stored property）が増えるか、増えるなら受け皿はどこか」。既存の 9 項目と同じく「該当しない」で済ませず理由を 1 行書く形式に揃える。
2. **PR 時**: `.claude/commands/quality-loop.md`（`git diff main...HEAD` を対象に PR 作成前へ回す既存フロー）から新レビュアーを呼ぶ。
3. **タスク完了時**: `.claude/commands/finish-task.md` の検証手順へ組み込む。

## 注意

`.claude/skills/review-design.md` は「サブタスクに分割した機能では、サブタスクごとに回す」と定めている。この配線でも同じ粒度が保たれること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 責務分離を見るサブエージェントが .claude/agents/ に追加され、既存 5 体と同じ作法（報告のみ・ツール構成）に揃っている
- [ ] #2 判断基準が docs/dev/rules/product-code.md の責務分離節を参照する形になっており、内容が二重管理されていない
- [ ] #3 review-design のチェックリストに、触る型グループの現行行数・追加見積もり・責務の増減を確認する項目が追加されている
- [ ] #4 quality-loop から新レビュアーが呼ばれる
- [ ] #5 finish-task の検証手順に組み込まれている
- [ ] #6 実際に 1 件の差分に対して回し、指摘が出るか妥当に出ないことを確認した記録が Implementation Notes にある
<!-- AC:END -->
