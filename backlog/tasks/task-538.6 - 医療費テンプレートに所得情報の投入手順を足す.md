---
id: TASK-538.6
title: 医療費テンプレートに所得情報の投入手順を足す
status: To Do
assignee: []
created_date: '2026-08-22 13:47'
updated_date: '2026-08-22 13:47'
labels: []
milestone: m-10
dependencies:
  - TASK-538.3
parent_task_id: TASK-538
priority: medium
ordinal: 788000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/public/templates/medical-expenses/README.md` の『data/income.tsv の仕様』は**列の定義だけがあり、値をどこから取ってどう入れるかが書かれていない**。他の TSV（medical-YYYY-氏名.tsv）には投入手順（Inbox → LLM に依頼 → 追記）があるのに、income.tsv だけ入口が無い。

## 何が足りないか

- **どの書類から取るか**: 給与所得者なら源泉徴収票。『支払金額』が `revenue`、『給与所得控除後の金額』が `income`、『源泉徴収税額』が `withheld` に対応する、という対応表は列の説明に書いてあるが、**源泉徴収票を投入する手順が無い**
- **どこへ入れるか**: 領収書は Inbox へスキャンを投げる運用があるが、源泉徴収票も同じ Inbox でよいのか、別扱いか
- **年に 1 回しか無い作業をどう思い出すか**: 医療費の取り込みは月次だが、これは年 1 回。TODO.md に置くのか、確定申告の作業の一部として扱うのか
- **給与以外の所得**: `kind` 列があるが給与しか例が無い。事業所得・年金がある場合に何を見るのか

## 判断が要る点

所得情報は医療費以上に機微（家族全員の年収が 1 ファイルに並ぶ）。**この構成のまま公開テンプレートに載せてよいか**を先に決める。選択肢は次のとおり。

1. 手順まで書く（読者の実用性は最も高い）
2. 列の定義だけ残し、投入は各自に委ねる（現状）
3. income.tsv 自体をテンプレートから外し、『足切りの判定に所得が要る』という説明だけ残す

## 前提

TASK-538.3 で運用を一巡させた結果を踏まえて書く（源泉徴収票の読み取りが領収書と同じ手順で通るかは未検証）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 income.tsv をテンプレートに残すか外すかを決め、理由を Notes に残す
- [ ] #2 残す場合、値の出どころ（源泉徴収票のどの欄か）と投入の手順が README に書かれている
- [ ] #3 年 1 回の作業をいつ行うかが運用の中に位置づけられている
<!-- AC:END -->
