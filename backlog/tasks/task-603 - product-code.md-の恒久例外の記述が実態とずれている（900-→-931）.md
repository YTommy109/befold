---
id: TASK-603
title: product-code.md の恒久例外の記述が実態とずれている（900 → 931）
status: To Do
assignee: []
created_date: '2026-09-08 15:33'
labels:
  - refactor
dependencies: []
ordinal: 875000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`docs/dev/rules/product-code.md` の責務分離節が、恒久例外の登録を「`ViewerWindowController`（上限 900 行）1 件のみ」と書いている。実際の `scripts/type-group-exceptions.txt` の上限は **931**（TASK-585 で 900 → 920、TASK-593 で 920 → 931 と動いた）。件数が 1 件であることは合っている。

例外ファイル自身が「上限は常に実測値へ張り付ける」と書いているとおり、この数値は今後も動く。文書側に数値を写すのをやめるか（「現在の登録は `ViewerWindowController` 1 件（上限は `scripts/type-group-exceptions.txt` を参照）」）、追随を機械で担保するかを決める。

行番号引用は `scripts/check-doc-citations.sh` が見ているが、**文中の数値が実態と合っているかは誰も見ていない**。同じ形のずれは他の規約文書にもありうる。

なお TASK-547 の /review-design（2026-09-09）でこのずれを見つけ、同じ節の数行下へ別の記述を追加した。修正自体は 1 語の書き換えで済む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `docs/dev/rules/product-code.md` の恒久例外の記述が実態と一致している
- [ ] #2 数値の追随をどう担保するか（機械検査を足す / 数値を文書から外す）を決め、理由を Notes に残してある
<!-- AC:END -->
