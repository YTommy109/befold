---
id: TASK-538.3
title: 架空データで運用を一巡させ、記事用のスクリーンショットを撮る
status: To Do
assignee: []
created_date: '2026-08-22 13:06'
updated_date: '2026-08-22 13:17'
labels: []
dependencies:
  - TASK-538.2
parent_task_id: TASK-538
priority: medium
ordinal: 785000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
記事に載せる素材を作る。同時に、**書いた手順が実際に通ることを確かめる**（ユーザーは『実際に動かしていない点に不安がある』と述べている。読者は手順どおりに試すので、未検証のまま出さない）。

## 一巡させる内容

架空の 4 人家族ぶんのサンプルで、README に書いた手順をそのまま実行する。

1. 領収書 PDF を用意する（架空の医療機関・金額。スキャン風の画像 PDF にすること——テキスト層があると読み取り手順の意味が変わる）
2. pdfimages で画像を取り出し、Pillow の ImageOps.autocontrast で整えて読む
3. 複数枚まとめた PDF を pypdf で分割する
4. data/medical-YYYY-氏名.tsv へ追記し、receipts/YYYY/氏名/ へリネームして移す
5. providers.md へ支払先を追記する

手順が実際と食い違ったら、TASK-538.2 の文書側を直す。

## スクリーンショット（befold の見せ場 3 つ）

- TSV のテーブル表示（Numbers で開かずに集計表を確認する）
- 領収書 PDF のプレビュー（集計表の receipt 列から対応する PDF を確かめる。サイドバーでフォルダをたどる様子も入れる）
- README / CLAUDE.md の Markdown 表示

差分表示は題材が git 管理外（iCloud Drive）なので使わない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 架空データで README の手順を一巡させ、通らなかった箇所は文書側を修正してある
- [ ] #2 befold の見せ場 3 つのスクリーンショットが揃っている
- [ ] #3 スクリーンショットに実在の氏名・医療機関名・金額・パスが写り込んでいない
- [ ] #4 サンプルデータ一式が、記事から持ち帰れる形（または再現手順）で残っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## site/temp はこの時点で存在しない（2026-08-22）

実行順を変更したため、このタスクに着手する頃には参照用の実データ（site/temp）は削除済み（TASK-538.5）。**元の運用文書は参照できない前提で進める。**

このタスクは『TASK-538.2 が書いた公開版の手順が実際に通るか』を確かめるもので、通らなければ**直すのは公開版の CLAUDE.md / README.md の側**。元文書との突き合わせではない。

未検証の手順が一時的に文書へ載ることは許容している（公開は TASK-538.4 なので、外に出る前に直せる）。
<!-- SECTION:NOTES:END -->
