---
id: TASK-428.2
title: ベースラインとの比較でラチェット判定を行い pre-commit で警告する
status: To Do
assignee: []
created_date: '2026-08-10 12:33'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: high
type: chore
ordinal: 669000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
前サブタスクで作った集計スクリプトにベースラインとの比較を追加し、型グループの行数が増えたとき・新規グループが閾値を超えたときに検知できるようにする。このサブタスクでの強制は pre-commit の警告どまり（コミットは通す）。ブロックは次サブタスクの CI で行う。

段階を分ける理由は、作業の途中段階でコミットが止まると `--no-verify` を使う圧力がかかり、フック自体が形骸化するため。手元では気づけるだけにして、外に出る手前で確実に止める。

## 判定の内容

- ベースラインに載っているグループ: ベースライン値を超えたら検知
- ベースラインに載っていない新規グループ: 閾値を超えたら検知
- ベースライン値を下回ったグループ: ベースラインが古くなるので、更新を促す。ここで落とすか警告に留めるかは実装者が決めて記録する（落とす方がラチェットは確実に締まるが、返済のたびに必ずベースライン更新のコミットが要る）

## 配線先

`scripts/setup-git-hooks.sh` が生成する pre-commit（現状は block-main-commits / swiftformat-lint / check-doc-symbols / check-task-id-uniqueness / check-analytics-query-guard の 5 本を `set -e` で直列実行）へ追加する。警告どまりにするため、既存 5 本と違い終了コードで落とさない実装にすること。

## 注意

`.claude/settings.json` の PreToolUse フックは `.swiftlint.yml` の編集をブロックしている。閾値の緩和で問題を回避する経路は塞がれている前提で設計してよい。ベースラインファイルにも同種の保護が要るかどうかを検討し、判断を記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ベースラインを超えて増加した型グループを検知して報告する
- [ ] #2 ベースラインに無い新規の型グループが閾値を超えたときに検知して報告する
- [ ] #3 pre-commit から実行され、検知しても終了コードでコミットを止めない
- [ ] #4 検知メッセージに、どのグループが何行から何行へ増えたかが含まれる
- [ ] #5 ベースラインを下回ったときの扱い（落とす／警告）の決定が理由つきで記録されている
- [ ] #6 --self-test が増加・新規超過・減少の 3 ケースを検証する
<!-- AC:END -->
