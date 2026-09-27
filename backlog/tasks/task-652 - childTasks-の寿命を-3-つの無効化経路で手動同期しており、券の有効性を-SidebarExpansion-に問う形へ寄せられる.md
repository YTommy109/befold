---
id: TASK-652
title: childTasks の寿命を 3 つの無効化経路で手動同期しており、券の有効性を SidebarExpansion に問う形へ寄せられる
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
priority: low
ordinal: 852000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。TASK-644 で「走行中の有効な取得だけを持つ」を不変条件にしたが、その維持はまだ `collapseFolder` / `reloadExpandedChildren` / `invalidateExpansion` の 3 経路と `loadChildren` の上書きで**手で**行っている（`SidebarTreePresenter.swift` の `childTasks` の doc がその 4 経路を列挙している）。このブランチでは「expansion と寿命を揃えるべき並走状態」の破れが 2 度出ている（dfeaf408 lastReveal / 9995a2b4 childTasks）。`.claude/CLAUDE.md`「同型のバグが 2 回目に出たら構造で塞ぐ … 判定の置き場所を変える」。

## 現状（検証済み）

- `SidebarExpansion.apply` は `generations[token.key] == token.generation, epoch == token.epoch` で有効性を判定している。同じ判定を外から問う API は無い。
- 券を無効にする経路が増えるたびに `childTasks` 側の掃除を書き足す必要があり、書き忘れると無効化済みの取得を `awaitSettled` が待ってハングする（TASK-644 と同じ失敗）。

## 方向

`childTasks` を `[String: (token, task)]` にし、`SidebarExpansion.isCurrent(_ token:)` を足す（`apply` 内のガードを 1 箇所へ切り出して共有）。`awaitSettled` は非 current の券を飛ばし、掃除は着地経路だけに残す。3 つの手動掃除は撤去する。TASK-644 のテスト（畳んだ配下の券が残ってもハングしない）はそのまま通ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `SidebarExpansion` に券の有効性を問う API があり、`apply` の判定と同じ実装を共有している
- [ ] #2 `collapseFolder` / `reloadExpandedChildren` / `invalidateExpansion` から `childTasks` の手動掃除が消えている
- [ ] #3 TASK-644 のハング再現テストが引き続き通る
<!-- AC:END -->
