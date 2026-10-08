---
id: TASK-683
title: docs/dev/viewer-ui.md「差分の比較基準」節を TASK-678/679 の実装に追随させる
status: To Do
assignee: []
created_date: '2026-10-08 08:49'
labels:
  - docs
dependencies:
  - TASK-680
  - TASK-681
priority: low
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high(2026-10-08)の指摘。現在仕様層の文書がコードと食い違っている。

- viewer-ui.md「差分の比較基準(TASK-353)」節の「▾ で基準を選ぶ(Menu(primaryAction:))」は、SidebarHeaderControls.changedFilesOnlyMenu の doc コメントが実機確認(色とチェックが出ない)で明示的に不採用とした形。実装は本体 button + 独立した Menu(Picker inline)
- 同じ節の表の「ラベルにその名前が出る」はツールバーのラベルを撤去済み(TASK-678)で古い
- TASK-679 で足した表示メニュー(表示 > 比較基準 サブメニュー)の入口が一切書かれていない
- TASK-678 の Final Summary も「Menu(primaryAction:) へ移し」と古く、TASK-679 の Notes には docs 更新の要否の判断が無い(.claude/CLAUDE.md「/finish-task 手順 5 … 更新不要と判断したならその理由を Notes に 1 行残す」に反する)

放置すると、次にこの節を読んだ人が primaryAction 前提で改修に入り、実機で潰した色/チェックの不具合を再発させる。TASK-680(選択肢の導出 1 本化)と TASK-681(ラベル・ツールチップの中身)で UI がもう一度動くので、その後に 1 回で書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer-ui.md の当該節が、サイドバーの ▾(button + 独立 Menu)と表示メニューの両入口、選択肢の規則(スタック全体は親≠デフォルトのときだけ)、縮退の見せ方(TASK-681 の決定)を現状どおりに記述している
- [ ] #2 Menu(primaryAction:) と「ラベルにその名前が出る」の記述が残っていない
- [ ] #3 markdownlint-cli2 と scripts/check-doc-citations.sh が通る
<!-- AC:END -->
