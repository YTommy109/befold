---
id: TASK-910
title: 空タブでもサイドバーの表示を維持する
status: To Do
assignee: []
created_date: '2026-11-07T06:38:00Z'
labels:
  - sidebar
  - tabs
  - ui
dependencies:
  - TASK-909
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
documentation:
  - docs/dev/viewer-ui.md
priority: high
type: bug
ordinal: 876000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーを表示した窓で ⌘T を押すと、新しい空タブにサイドバーが出ない（2026-11-07 実機確認）。サイドバーの表示はユーザーの操作で決まるものなので、新しいタブでも維持されるのが期待する動作。PR #750 の空タブは `NSHostingController` だけを持ち split view が無いため、タブを切り替えるだけでサイドバーが消えて本文の位置も動く。同じ理由で、`SidebarInheritance.seed(from:)` は起点が `ViewerWindowController` のときしか材料を返さないので、空タブを文書へ置き換えるとフォルダ一覧と展開状態を引き継げないはず（コードからの判断で未再現）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーを表示した窓で ⌘T またはタブバーの + を使うと、空タブにも起点と同じフォルダのサイドバーが表示される
- [ ] #2 サイドバーを閉じた窓から開いた空タブではサイドバーが閉じている
- [ ] #3 空タブのサイドバーでファイルを選ぶと、その空タブが同じ位置で文書タブに置き換わる
- [ ] #4 空タブを文書へ置き換えたとき、サイドバーの開閉・一覧・ツリーの展開状態が保たれる
- [ ] #5 起点の窓が無い ⌘T での動作が決まり、docs/dev/viewer-ui.md に記載されている
- [ ] #6 ファイルを選ぶまで WebKit とファイル監視を作らないという空タブの性質が保たれる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
制約: `ViewerWindowAssembler` のサイドバー組み立ては `ViewerWindowController` を前提にし、そのコントローラは fileURL が必須。新しい状態と経路を足す変更なので着手前に /review-design を回す。
<!-- SECTION:NOTES:END -->
