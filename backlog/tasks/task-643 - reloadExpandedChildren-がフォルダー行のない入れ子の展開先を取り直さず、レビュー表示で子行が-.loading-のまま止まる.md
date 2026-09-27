---
id: TASK-643
title: reloadExpandedChildren がフォルダー行のない入れ子の展開先を取り直さず、レビュー表示で子行が .loading のまま止まる
status: Done
assignee: []
created_date: '2026-09-27 07:23'
updated_date: '2026-09-27 07:31'
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
- [x] #1 `a` と `a/deep` を同時に展開し、`a` の子リストが着地する前に `reloadExpandedChildren` を挟んでも、両方の子リストが着地して行に出るテストがある（子リスト取得をゲートで止めて再現する）
- [x] #2 TASK-451 の振る舞い（Finder 側で消えたフォルダーの展開キーへ列挙が飛ばない）を守るテストが引き続き通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
reloadExpandedChildren のスキップ条件を「一覧に行が無い」から「一覧に行が無く、かつ答え(.loaded/.failed)を持っている」へ狭める。新しい状態は足さず、既存の children[key] == .loading で「親の着地待ち」を判別する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: 候補に挙がっていた「親キーが展開中なら取り直す」は、消えたフォルダーの親も展開中なら TASK-451 の防止が崩れる。「スキップしたキーを親着地時に再発行」は保留券という新しい状態が要る。既存の children[key] == .loading(= 初回取得が走行中で、今 epoch で捨てた)だけを再発行条件に足せば状態も経路も増えない。.loaded/.failed のキーは古い答えを出し続けられるので飛ばしても止まらない。消えたフォルダーの初回取得中に取り直しが来た場合は 1 回だけ列挙が飛んで .failed が着地し、以後は飛ばされる(上限あり)。
検証: 新規テスト reloadReissuesNestedExpansionAwaitingParent は修正を外すと失敗(entries に leaf が無い)、入れると成功。TASK-451 の reloadSkipsFoldersMissingFromListing は通過。swift test 全体 2003 + 72 件成功。swiftformat 差分なし・変更 2 ファイルの swiftlint 0 件。
設計文書: native-app-design.md 等は reloadExpandedChildren のスキップ条件に言及していないため更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarTreePresenter.reloadExpandedChildren が、子リストの初回取得中(.loading)のキーを一覧に行が無くても取り直すようにした。入れ子の一括展開で深い側が .loading のまま止まる問題を解消。ゲートで再現するテストを追加(修正なしで失敗を確認)、TASK-451 のテストと全テスト通過。
<!-- SECTION:FINAL_SUMMARY:END -->
