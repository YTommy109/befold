---
id: TASK-485.13
title: isRendering の防御的クリア 3 箇所を、render 完了通知の一本化で置き換える
status: To Do
assignee: []
created_date: '2026-08-17 14:05'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 747000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`viewer-src/jump.ts:206` ほか、isRendering フラグが open / close / refresh の 3 つの入口で強制クリアされている。原因は `render.ts:93-94` が `_mmdJump.isOpen()` のときしかジャンプコントローラへ render 完了を通知しないこと。open() の「もう render は着地しているはず」という仮定は mermaid render 中（大きい図で数秒）には偽で、その窓で開くと DOM スワップ進行中に isRendering がクリアされ、見出しレベルのトグルが mid-render DOM に対して rebuild() を走らせうる——このフラグが守るはずのハザードそのもの（transient: バーが開いていれば `render.ts:93` の着地時 refresh が後で正すが、それは偶然）。

## 提案（レビューの指摘どおり）

`_mmdFindRefreshAfterRender` から無条件に `_mmdJump.refresh` を呼び、refresh が最初にフラグをクリアする。これで setter は invalidate の 1 箇所、clearer は refresh の 1 箇所になり、3 つの防御的リセットとそのコメントを削除できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 isRendering の setter が invalidate、clearer が refresh の各 1 箇所になっている
- [ ] #2 open / close / refresh 入口の防御的リセットと説明コメントが削除されている
- [ ] #3 render 進行中にバーを開いてレベルをトグルしても mid-render DOM への rebuild が起きないことをテストで固定する
<!-- AC:END -->
