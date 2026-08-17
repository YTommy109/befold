---
id: TASK-485.6
title: ジャンプバー表示中に修飾キー付き Enter やリンク上の Enter まで奪ってしまう
status: To Do
assignee: []
created_date: '2026-08-17 14:02'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 740000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`resolveJumpNavigationKey`（`viewer-src/keyboard.ts:89-100`）は key / openBar / shiftKey / isComposing / keyCode しか見ず、modifier キー（metaKey / ctrlKey / altKey）とイベントターゲットを無視する。document レベルのハンドラ（`keyboard.ts:109-117`）が preventDefault するため、ジャンプバーが開いている間は Cmd/Ctrl/Alt+Enter のチョードや、Tab でフォーカスしたリンク上の Enter（markdown-it の出力はタブ移動可能）まで「ジャンプ移動」として消費される。

find バーは Enter の処理を自分の input 要素の keydown リスナーにスコープしており（`viewer-src/find.ts:442-447`）、この問題を回避している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ジャンプバー表示中でも modifier 付き Enter（Cmd/Ctrl/Alt+Enter）は既定動作のまま通る
- [ ] #2 フォーカスされたリンク上の Enter はリンクの既定動作になり、ジャンプ移動に消費されない
- [ ] #3 素の Enter / Shift+Enter によるジャンプ前後移動は引き続き動く
- [ ] #4 jest テストが上記の分岐を固定する
<!-- AC:END -->
