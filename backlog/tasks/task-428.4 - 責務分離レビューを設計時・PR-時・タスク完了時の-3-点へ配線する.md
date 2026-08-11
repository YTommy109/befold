---
id: TASK-428.4
title: 責務分離レビューを設計時・PR 時・タスク完了時の 3 点へ配線する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:34'
updated_date: '2026-08-11 04:59'
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
- [x] #1 責務分離を見るサブエージェントが .claude/agents/ に追加され、既存 5 体と同じ作法（報告のみ・ツール構成）に揃っている
- [x] #2 判断基準が docs/dev/rules/product-code.md の責務分離節を参照する形になっており、内容が二重管理されていない
- [x] #3 review-design のチェックリストに、触る型グループの現行行数・追加見積もり・責務の増減を確認する項目が追加されている
- [x] #4 quality-loop から新レビュアーが呼ばれる
- [x] #5 finish-task の検証手順に組み込まれている
- [x] #6 実際に 1 件の差分に対して回し、指摘が出るか妥当に出ないことを確認した記録が Implementation Notes にある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .claude/agents/responsibility-reviewer.md を既存 5 体と同じ作法で新設し、判断基準は product-code.md の責務分離節を参照させる
2. review-design のチェックリストへ項目 10（型グループの現行行数・追加見積もり・責務の増減）を追加する
3. quality-loop の Round 1 から並行起動させる
4. finish-task の検証手順（手順 2）へ組み込む
5. 実在の差分に対して 1 回回し、結果を Notes へ記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定事項（TASK-428.4）

- **判断基準は書き写さず参照させた**。エージェント定義は `docs/dev/rules/product-code.md` の責務分離節を「必ず Read してから判断する」と指示するのみで、基準の内容自体は持たない。二重管理を避けるため（AC #2）。
- **行数判定との役割分担を定義へ明記した**。「行数閾値を通っているので問題なし」という結論を書かないよう明示的に禁止している。行数は CI が見るので、このレビュアーが同じことを言うと役割が重複し、かつ「通っている＝責務が分かれている」という誤った結論を生む。
- **3 点の配線先**:
  - 設計時: `.claude/skills/review-design.md` のチェックリストへ項目 10 を追加（既存 9 項目と同じ「該当しないなら 1 行で理由を書く」形式）。型グループの現行行数を実測するコマンドを埋め込み、プロトコル準拠・注入クロージャ・stored property の増減を答えさせる。
  - PR 時: `.claude/commands/quality-loop.md` の Round 1 で並行起動し、指摘を rule-violation タグで既存の指摘リストへ合流させる（別ラウンドを増やすと修正ループが伸びるため合流にした）。
  - タスク完了時: `.claude/commands/finish-task.md` の手順 2（テストの空振り確認と同じ節）へ組み込み。
- **サブタスク粒度は保たれる**: 設計時の配線先が review-design のチェックリスト本体なので、「サブタスクごとに回す」という既存規定（同スキル 23-26 行）がそのまま効く。

## 実地確認（AC #6）

コミット e94161d（レビュー対応で肥大化した SidebarNavigator 系を分割）へ実際に回した。**指摘が出た。しかも狙いどおりの型**:

- High: この分割は責務分離ではなく file_length 回避。型グループ合計 446 → 449 行で実質不変、SidebarNavigator が抱える関心は 8 個のまま（Base Directory / Git Status / File List / 選択 + extension 4 本）。TASK-411 の原文と同型と判定した。分割案として git 関連（stored property 6 個・クロージャ 3 個）の SidebarGitStatusCoordinator への切り出しを名指しで提案。
- Medium: ファイル分割の代償で private が 2 箇所緩んだ（host / folderEntryURL）。+History が触る本体メンバが stored 3 + ヘルパー 3 で本体と不可分であることの証拠と指摘。
- Medium: 共有テストスタブ RecordingWatcher が専用ファイル（既存の SidebarNavigatorTestStubs.swift）ではなくスイートファイルに置かれている。
- Info: クロージャ注入 5 個は規約の 3 個超過に既に該当（差分での増加ではない）。プロトコル準拠・stored property の増加なし。

いずれも `scripts/check-type-group-size.sh` の行数判定では出せない指摘であり、意味レイヤーが機能することを確認できた。指摘内容は TASK-426（ViewerWindowManager）と同種の返済対象で、SidebarNavigator の返済タスクは未起票。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
責務分離レビュアー responsibility-reviewer を新設し、設計時（review-design のチェックリスト項目 10）・PR 時（quality-loop の Round 1 と並行）・タスク完了時（finish-task の手順 2）の 3 点へ配線した。判断基準は product-code.md の責務分離節を参照させ、内容は書き写していない。

検証: コミット e94161d に対して実際に起動し、High 1 件 / Medium 2 件 / Info 1 件の指摘を得た。High は『この分割は責務分離ではなく file_length 回避（型グループ 446 → 449 行で関心は 8 個のまま）』という、行数判定では出せない狙いどおりの型で、SidebarGitStatusCoordinator への切り出しまで名指しで提案していた。markdownlint-cli2 は全 70 ファイル 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
