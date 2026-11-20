---
id: TASK-914
title: 空タブのツリーで子のファイルを選ぶと、文書タブのサイドバーのルートと展開が失われる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T11:27:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowManager+OpenViewer.swift
  - BefoldApp/befold/App/SidebarInheritance.swift
documentation:
  - docs/dev/viewer-ui.md
priority: high
type: bug
ordinal: 880000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769（PR #764〜#768）のレビューで検出。空タブのツリー表示で、展開したサブフォルダ内のファイルを選ぶと、置き換わった文書タブのサイドバーがそのサブフォルダへルートごと移り、展開も消える。文書タブで同じ行を選んでも移動しないので（`SidebarNavigator.syncAfterSwitch` / TASK-465）、空タブを挟んだときだけ挙動が変わる。docs/dev/viewer-ui.md の「開閉・一覧・展開はそのまま文書タブへ渡る」と TASK-910 の AC #4 にも反する。

裏付け（コード参照・実機未確認）: `ViewerWindowAssembler.makeSidebarNavigator` は `currentDirectory` を `fileURL.deletingLastPathComponent()` にする。`SidebarListingSeed.canApply(to:)` は同じディレクトリしか通さず、`SidebarNavigator.attach` はその guard で return するので `tree.adoptExpansion` まで届かない。`seedReadsBlankTabSidebar` は採取した seed の中身しか見ていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 空タブのツリーで展開したフォルダ内のファイルを選ぶと、文書タブのサイドバーのルートと展開が選ぶ前と同じである
- [x] #2 置き換わった文書タブで、そのファイルの行が選択されている
- [x] #3 空タブから置き換えたときのルートと展開を確かめる自動テストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 空タブを同じ位置で置き換えるとき、空タブのサイドバーの位置（表示中のフォルダと rootDirectory）を引き継ぐ。条件は文書タブと同じ isReachableInCurrentListing（今の一覧から選べるか）で、位置は一覧の引き継ぎのフォルダから作る。一覧を引き継げないなら位置も引き継がない（位置だけだと展開が落ちる）。
code-review high の指摘 7 件のうち、判定の広さ（閉じたツリーや一覧の外のファイルでも引き継ぐ）、展開だけ落ちる形、ルート / での取りこぼし、束の 2 段階の組み立て、境界のテスト不足、使われない既定値を直した。並び順や不可視ファイルの設定が空タブと新しいタブで違うと一覧の引き継ぎが通らない点は残した（その場合は位置も引き継がないので、選んだファイルは見える）。
ViewerWindowController の init は一覧と展開の 2 引数を Seed 1 つにまとめた。makeSidebarNavigator は共有依存と git の読み手で受け、main から残っていた引数の数の警告を 1 件解消した。
実測: 位置の引き継ぎを外すとルート・最上位・展開の 3 件が落ち、到達判定を外すと境界のテストが両方落ちる。swift test 1998 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件（既存 1 件解消）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
空タブのツリーで子のファイルを選んでも、置き換えた文書タブのサイドバーのルートと展開が保たれるようにした。文書タブと同じく、今の一覧から選べるファイルのときだけ位置を引き継ぐ。
<!-- SECTION:FINAL_SUMMARY:END -->
