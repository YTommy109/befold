---
id: TASK-311
title: サイドバーで Cmd+↑ を上位フォルダーへ移動するショートカットに割り当てる(Finder 準拠)
status: To Do
assignee: []
created_date: '2026-08-05 02:34'
labels: []
dependencies: []
priority: medium
ordinal: 509000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListView.handleKey(_:)(FileListView.swift:308-321)は KeyPress のキーだけで分岐しており、修飾キーを見ていない。.leftArrow / "h" / .delete がいずれも navigateToParent()(:372-378)を呼ぶ実装のため、Cmd+←(左矢印)は既に(意図せず)navigateToParent と同じキーにマッチしている。ユーザー確認済み: この重複はそのままでよい。

一方 Cmd+↑(上矢印)は現状 .upArrow の case(→ selectPrevious())にそのままマッチしてしまい、Finder のような「上のフォルダーへ移動」動作にはならない。修飾キーなしの ↑ / k との衝突を避けるため、handleKey に修飾キーの判定を加え、Cmd+↑ のときだけ navigateToParent() を呼ぶ必要がある。

navigateToParent()(:372-378)は model.visibleEntries の .parentNavigation エントリの有無で境界(ホームディレクトリ直下など、親へ移動できない場合)を扱っており、Cmd+← 同様にこの関数をそのまま再利用すれば境界条件は自然に揃う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーにフォーカスがある状態で Cmd+↑ を押すと、現在のディレクトリの親フォルダーへ移動する(navigateToParent 相当の挙動)
- [ ] #2 修飾キーなしの ↑ / k は従来どおり選択を1つ上へ移動する(回帰しない)
- [ ] #3 Cmd+← は従来どおり navigateToParent として動作し続ける(重複は許容、変更しない)
- [ ] #4 親フォルダーが無い(ホームディレクトリ境界など)場合、Cmd+↑ は navigateToParent の既存の境界条件と同じ挙動になる(何も起きない)
<!-- AC:END -->
