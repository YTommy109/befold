---
id: TASK-558
title: 共有 Preference の init 引数からデフォルト値を外す
status: To Do
assignee: []
created_date: '2026-08-27 05:28'
labels: []
dependencies: []
ordinal: 808000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerWindowManager.init` と `ViewerWindowController.init` の `codeFontPreference` には `= CodeFontPreference()` のデフォルト値が付いている。これは TASK-319（`DiffDisplayPreference` が窓ごとに生成され 2 窓でトグルが同期しなかった）と同型の穴で、**渡し忘れがコンパイルエラーにならず静かに別インスタンスになる**。

`AppStores` の doc コメント自体が「個別に引数で配ると渡し忘れがコンパイルエラーにならないため、束ねた 1 個を配る」と書いており、デフォルト値付きの引数はその方針と食い違っている。

TASK-557.2 で足した `csvNumberFormatPreference` は既にデフォルト値を付けていない（実装前の /review-design で指摘した）。既存分を揃える。

## 対象

`rg 'Preference = \w+Preference\(\)'` で洗う。少なくとも `codeFontPreference` の 2 箇所（ViewerWindowManager / ViewerWindowController）。`findOptionsPreference` にも同じ形がある（`= FindOptionsPreference()`）ので、共有前提かどうかを 1 件ずつ確かめる。

## 注意

デフォルト値を外すと実構築サイト（本番 1 + テスト 4〜5）へ引数追加が要る。TASK-557.2 の実測では `ViewerWindowManager` の実構築は 5 箇所だけで、`grep -c 'ViewerWindowManager('` の 73 件は大半が `MockedViewerWindowManager(` の部分一致だった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 共有前提の Preference / Store を受け取る init 引数にデフォルト値が残っていない
- [ ] #2 デフォルト値を外した引数について、実構築サイトがすべて AppStores の同じインスタンスを渡している
- [ ] #3 対象を洗った結果（外した引数と、共有前提でないため残した引数）が Implementation Notes に列挙されている
<!-- AC:END -->
