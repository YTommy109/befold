---
id: TASK-538.4
title: 記事本文を書いて公開する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-22 13:06'
updated_date: '2026-08-23 07:33'
labels: []
milestone: m-10
dependencies:
  - TASK-538.1
  - TASK-538.2
  - TASK-538.3
parent_task_id: TASK-538
priority: medium
ordinal: 786000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-538.1 の器に、TASK-538.2 のテンプレートと TASK-538.3 の素材を使って記事本文を載せる。

## 記事の骨子（案）

1. **掴み**: 家族に渡す説明が 3 行で済む。『領収書をもらったら iPhone のファイルアプリでスキャン。名前も日付も気にしなくていい』
2. **困りごと**: 医療費控除は 1 年分の領収書が貯まるが、集計は年に 1 回しかやらない。溜めると読めない、都度やると続かない
3. **仕組み**: Inbox に投げるだけ → 月末に Claude へ依頼 → TSV に追記され receipts/ へリネーム移動される。プログラムは 1 行も書いていない
4. **befold が効くところ**: (a) TSV を Numbers で開かずに表で見る——開いて保存し直すと先頭ゼロや日付形式が変わる問題を避ける (b) 集計表の receipt 列から領収書 PDF をすぐ確かめる (c) LLM 向けの規約文書（CLAUDE.md / README.md）を人が読む
5. **持ち帰り**: テンプレートと、領収書の 5 年保存義務の注意
6. **導線**: befold のダウンロード

## 免責・注意の表現

税務の手続きに関わる内容なので、『最終的な判断は国税庁の情報と税務署に確認すること』の旨を入れる。国税庁ページへの出典リンクは TASK-538.2 のテンプレート側にもあるが、記事本文にも置く。

## 触れないこと

- 差分表示（題材が git 管理外なので使えない）
- 実在の家族構成・医療機関
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 記事が公開され、紹介サイトから到達できる
- [ ] #2 befold の見せ場 3 つが、それぞれスクリーンショット付きで記事に登場する
- [ ] #3 テンプレート（CLAUDE.md / README.md）を読者が持ち帰れる導線がある
- [ ] #4 税務判断についての注意書きと国税庁への出典リンクがある
- [ ] #5 記事末尾に befold のダウンロード導線がある
- [ ] #6 公開後、befold analytics のダッシュボードで記事のアクセス数が実際に計上されていることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-541（記事のドラフト管理）が入れば、本文を書きかけでコミットしてレビューを受けられる。着手時に 541 の状態を確認すること。
<!-- SECTION:NOTES:END -->
