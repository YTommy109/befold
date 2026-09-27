---
id: TASK-644
title: >-
  SidebarTreePresenter.childTasks の寿命が expansion の寿命と揃っていない（畳んだ配下の券が残る／完了済みの
  Task を保持し続ける）
status: To Do
assignee: []
created_date: '2026-09-27 07:24'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: medium
ordinal: 844000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-642（commit d34fc0c5）で `SidebarTreePresenter.childTasks`（pathKey ごとの走行中の子リスト取得）を持たせ、`awaitSettled` がそれを待つようにした。`/code-review high` が寿命の取りこぼしを 2 件指摘し、コードで裏を取った。同型 2 件なので個別修正ではなく、寿命の規則を 1 箇所へ寄せる（`.claude/CLAUDE.md`「同型のバグが 2 回目に出たら構造で塞ぐ」）。

## 現状（検証済み）

1. **畳みの取りこぼし。** `collapseFolder(key)` は `childTasks[key] = nil` だけを外す。一方 `SidebarExpansion.collapse(key)` は `isKey(_:within:)`（`key` 自身と `key + "/"` 接頭辞）で**配下の展開もすべて捨てる**。配下の券は generation が進んで無効化済みだが、その Task は `childTasks` に残る。`awaitSettled` は `childTasks.first` から順に待つので、`a` → `a/deep` を展開（`a/deep` の lister をゲートで止める）→ `a` を畳む → `awaitSettled()` の順で、無効化済みの取得を待ってハングする。これは `childTasks` の doc が「待たないため」と書いている、まさにその場合。
2. **完了済みの保持。** `childTasks` のエントリを外すのは `awaitSettled`（テスト専用）・`collapseFolder`・`invalidateExpansion` だけ。プロダクトでは子リストが着地しても Task ハンドルが残り、フォルダーが展開されている間ずっと保持される（レビュー表示の 400 フォルダーなら 400 個の完了済み `Task<Void, Never>` を窓ごとに保持し、取り直しのたびに上書きで入れ替わる）。読む者はいない。

## 方向

「`childTasks` は走行中の取得だけを持つ」を不変条件にする。着地時に自分のエントリを外す（`expansion.apply` が受け付けたか、または token の世代を比較して、同じ Task なら外す）。畳み・無効化は `SidebarExpansion` が捨てたキーの集合をそのまま `childTasks` にも適用する（`collapse` が捨てたキーを返す、または同じ接頭辞規則で外す）。規則を presenter と expansion で二重に書かない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `a` → `a/deep` を展開し `a/deep` の子リスト取得をゲートで止めたまま `a` を畳んだ後、`awaitSettled()` がハングせず戻るテストがある
- [ ] #2 子リストが着地した後の `childTasks` にそのキーのエントリが残らない（走行中の取得だけを持つ）ことを測るテストがある
- [ ] #3 `childTasks` の doc コメントが「走行中の取得だけを持つ」という不変条件と、それを守っている経路を述べている
<!-- AC:END -->
