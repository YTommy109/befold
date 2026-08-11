---
id: TASK-454
title: 重複した pathKey があると、リンク行と実体行の両方が展開扱いになる
status: To Do
assignee: []
created_date: '2026-08-11 21:45'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 679000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
pathKey は resolvingSymlinksInPath() で解決した実体パスのため、同一フォルダー内にシンボリックリンクと実体が並ぶと 2 行が同じキーを持つ（TASK-450 の調査で確定）。

行の組み立て SidebarRowBuilder.Flattening.append（BefoldApp/befold/Viewer/SidebarRowBuilder.swift:106-113）は expanded.contains(entry.pathKey) で開閉を決めるため、片方を展開すると**もう一方の行も展開済みの見た目になる**。子行が実際に並ぶのは visited.insert が通る最初の 1 行だけなので、後の行は「三角は開いているのに子が出ない」状態になる。

同様に SidebarExpansion の children / expandedKeys もキー単位のため、リンク行と実体行を別々に開閉できない。

TASK-450 / TASK-451 の範囲外として切り出したもの（あちらは引き当て述語と再列挙の話で、開閉状態の粒度には触れていない）。優先度が low なのは、同一フォルダー内にリンクと実体が並ぶ構成自体が稀で、症状も見た目の不整合にとどまるため。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一キーの行が複数あるとき、展開したのはどの行かを区別できる（または区別しない方針を doc とテストで固定する）
- [ ] #2 三角が開いているのに子が出ない行が生じないことをユニットテストで担保している
<!-- AC:END -->
