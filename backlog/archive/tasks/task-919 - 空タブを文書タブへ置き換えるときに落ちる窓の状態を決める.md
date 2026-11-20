---
id: TASK-919
title: 空タブを文書タブへ置き換えるときに落ちる窓の状態を決める
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T11:36:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/SidebarInheritance.swift
documentation:
  - docs/dev/viewer-ui.md
priority: low
type: bug
ordinal: 885000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。`SidebarInheritance.Seed` が運ぶのは一覧・展開・開閉だけなので、空タブで操作した比較基準・戻る/進む履歴・`rootDirectory` は置き換えで失われる。比較基準を変えてからファイルを選ぶと既定値へ戻り、git のバッジが変わる。フォルダを移動してからファイルを選ぶと、文書タブの「戻る」で移動前のフォルダへ戻れない。docs/dev/viewer-ui.md は比較基準が既定値から「始める」ことだけを決めていて、利用者が変えた値を置き換えで捨てるかどうかは決めていない。

裏付け（コード参照・実機未確認）: `BlankTabWindowController.comparisonTarget` の読み手は空タブの内側だけで、`ViewerWindowManager.makeController` は `ViewerStore` の既定値で文書タブを作る。履歴は `SidebarNavigator` ごとの `SidebarHistoryController` が持つ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 比較基準・履歴・rootDirectory のそれぞれについて、引き継ぐか捨てるかが決まり docs/dev/viewer-ui.md に書かれている
- [x] #2 引き継ぐと決めたものは、置き換えの後も保たれることを自動テストで確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: 比較基準は引き継ぐ、rootDirectory は引き継ぐ（TASK-914 の位置と一緒に、今の一覧から選べるときだけ）、戻る/進む履歴は引き継がない（新しいタブはどの経路でも履歴を空で始めるので揃える）。既存のタブを使うときはそのタブの値のまま、一括オープンの 2 つ目以降は既定値から始める。いずれも viewer-ui.md に記載した。
code-review high: 比較基準を窓の生成後に当てていたため、最初の git 状態と差分の取得が既定値で走り、CLI の --compare を上書きする順序でもあった。init の中で、サイドバーの生成と CLI の上書きより前に当てるよう直した。置き換えのときだけ使う 2 つの値は Seed.Replacement にまとめ、型の説明を更新した。文書の改行抜けも直した。git の取得そのものを測るテストは、取得の入口を差し替える仕組みが無いので見送った。
BlankTabSidebarTests が type_body_length を超えたので、置き換えに関するテストを BlankTabReplacementTests へ分けた（件数は 15 のまま）。
実測: 引き継ぎを外すと replacedDocumentKeepsComparisonTarget が落ちる。swift test 1999 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
空タブを文書タブへ置き換えるときに落ちていた状態の扱いを決めた。比較基準と rootDirectory は引き継ぎ、戻る/進む履歴は新しいタブの規則に揃えて引き継がない。
<!-- SECTION:FINAL_SUMMARY:END -->
