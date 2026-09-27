---
id: TASK-643
title: reloadExpandedChildren がフォルダー行のない入れ子の展開先を取り直さず、レビュー表示で子行が .loading のまま止まる
status: To Do
assignee: []
created_date: '2026-09-27 07:23'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
priority: medium
ordinal: 843000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637〜642 の実装（commit c1de117a〜33f904a3）に対する `/code-review high` の指摘。コードで裏を取った。

## 現状（検証済み）

- `SidebarTreePresenter.reloadExpandedChildren` は `expansion.invalidateChildren()` で epoch を進めて走行中の子リスト取得をすべて無効化したうえで、`fileListModel.folderEntryURL(forKey:)` が nil のキー（いまの一覧にフォルダー行が無いキー）は取り直しをスキップする（TASK-451 の、消えたフォルダーへ列挙が飛ぶのを防ぐ判定）。
- レビュー表示の `revealChangedFolders` は `a` と `a/deep` のような入れ子の祖先を**同時に** `expandFolder` する。`a/deep` の行は `a` の子リストが着地するまで一覧に無い。
- この間に `refreshFileList`（ウィンドウのキー化・改名・並び替え等）が走ると、`a` は取り直されるが `a/deep` はスキップされ、元の取得は epoch ガードで捨てられる。`children[a/deep]` は `.loading` のまま残り、`a` が着地した後も次の無関係な取り直しまでスピナーが消えない。
- TASK-637 以前もユーザーが 2 階層を同じ取り直し窓の中で開けば同じことが起きたが、レビュー表示は入れ子の一括展開を既定の経路にした（400 フォルダー / 80ms の実測）ので、露出頻度が上がっている。

## 方向

TASK-451 の判定（消えたフォルダーへ飛ばさない）と、まだ行が無いだけの展開先（親の着地待ち）を区別する。候補: 行が無くても親キーが展開中なら取り直す／スキップしたキーの `.loading` を捨てて親着地時に再発行する。どちらでも「無効化したのに再発行しない券」を作らないことが要点。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `a` と `a/deep` を同時に展開し、`a` の子リストが着地する前に `reloadExpandedChildren` を挟んでも、両方の子リストが着地して行に出るテストがある（子リスト取得をゲートで止めて再現する）
- [ ] #2 TASK-451 の振る舞い（Finder 側で消えたフォルダーの展開キーへ列挙が飛ばない）を守るテストが引き続き通る
<!-- AC:END -->
