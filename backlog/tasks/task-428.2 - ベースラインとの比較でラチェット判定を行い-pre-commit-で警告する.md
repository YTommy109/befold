---
id: TASK-428.2
title: ベースラインとの比較でラチェット判定を行い pre-commit で警告する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:33'
updated_date: '2026-08-11 04:51'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: high
type: chore
ordinal: 104200
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
- [x] #1 ベースラインを超えて増加した型グループを検知して報告する
- [x] #2 ベースラインに無い新規の型グループが閾値を超えたときに検知して報告する
- [x] #3 pre-commit から実行され、検知しても終了コードでコミットを止めない
- [x] #4 検知メッセージに、どのグループが何行から何行へ増えたかが含まれる
- [x] #5 ベースラインを下回ったときの扱い（落とす／警告）の決定が理由つきで記録されている
- [x] #6 --self-test が増加・新規超過・減少の 3 ケースを検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. check-type-group-size.sh に --check（ベースライン比較）と --update-baseline を足す
2. 増加/新規超過/減少の 3 判定を --self-test へ追加する
3. 落とさないラッパ warn-type-group-growth.sh を作り pre-commit へ配線する
4. ベースラインファイルの保護要否を判断して記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定事項（TASK-428.2）

- **減少は落とさず警告（終了コード 2）に留めた**。返済のたびにベースライン更新のコミットを強制すると、分割作業の途中でフックが赤くなり続けて `--no-verify` を常用する圧力になる。古いベースラインが許すのは「元の値まで戻る」ことだけで無制限の増加ではないため、リスクは限定的。更新は `--update-baseline` の 1 コマンドで済むようにして摩擦を下げた。終了コードは 0=問題なし / 1=違反（増加・新規超過）/ 2=ベースラインが古い、の 3 値。
- **ベースラインファイルにも編集ガードを入れた**。`.claude/settings.json` の PreToolUse に `*type-group-baseline.txt` を追加し、Edit/Write での直接書き換えをブロックする（.swiftlint.yml と同じ扱い）。理由: 閾値の緩和経路が塞がれていても、ベースラインの数値を手で書き換えれば同じ回避ができるため、穴を残すと機構全体が意味を失う。`--update-baseline` は Bash 経由なのでブロックされず、正規の更新経路だけが残る。
- **ベースラインからグループが消えた場合（消滅）も終了コード 2 の警告**。ファイル削除やリネームで起きる正常な変化であり、落とす理由がない。
- **pre-commit は警告のみ（set -e を付けず、明示的に exit 0）**。既存 5 本と違い終了コードで落とさない。self-test も毎回通し、判定が壊れた状態でグリーンになるのを防ぐ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
check-type-group-size.sh に --check（ベースライン比較）/ --update-baseline を追加し、落とさないラッパ scripts/warn-type-group-growth.sh を pre-commit へ配線した。

検証:
- --self-test が増加・新規の閾値超過・減少の 3 ケースを一時ツリーで検証して OK（終了コードとメッセージ本文の両方を確認）
- 実データで ViewerStore を 100 行と偽ったベースラインを与え、『増加: .../ViewerStore が 100 行 → 492 行（+392）』と 11 件の新規閾値超過が報告され、ラッパの終了コードは 0 であることを確認
- 変更前の正規ベースラインでは --check が終了コード 0
- setup-git-hooks.sh を再実行し、pre-commit に warn-type-group-growth.sh が含まれることを出力で確認

ベースラインの手編集は .claude/settings.json の PreToolUse へ *type-group-baseline.txt を追加してブロックした。
<!-- SECTION:FINAL_SUMMARY:END -->
