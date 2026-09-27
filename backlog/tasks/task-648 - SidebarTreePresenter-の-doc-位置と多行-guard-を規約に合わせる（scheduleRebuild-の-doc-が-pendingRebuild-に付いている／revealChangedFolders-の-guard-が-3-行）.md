---
id: TASK-648
title: >-
  SidebarTreePresenter の doc 位置と多行 guard を規約に合わせる（scheduleRebuild の doc が
  pendingRebuild に付いている／revealChangedFolders の guard が 3 行）
status: To Do
assignee: []
created_date: '2026-09-27 07:24'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
priority: low
ordinal: 848000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637〜638 の実装に対する `/code-review high` の指摘のうち、`SidebarTreePresenter.swift` 内で完結する体裁の 2 件。

## 現状（検証済み）

1. `scheduleRebuild` のまとめ方（12ms × 400 回 → 80ms の実測、「次のメインアクター実行へ遅れるがその時点の `lastListing` を読むので古い材料で組むことはない」という不変条件）を述べた doc コメントが、stored property `pendingRebuild` に付いている。メソッド `scheduleRebuild` 自体には doc が無い。Quick Help は Task? のプロパティにまとめ方を表示し、読者が引くメソッドには何も出ない。
2. `revealChangedFolders` の先頭 `guard display.layoutMode == .tree, display.showChangedFilesOnly, let status = fileListModel.gitStatus else {` が 3 行にまたがる。`.claude/CLAUDE.md`「Swift コーディング規約」は多行 `if`/`guard` を「1 行化かヘルパー抽出で避ける」（swiftformat が `{` を独立行へ送り swiftlint の `opening_brace` が鳴る往復の元）としている。`BefoldApp/befold/App/` で同形の多行 guard はこの 1 箇所だけ。

## 方向

1 は doc の段落を `scheduleRebuild` へ移し、「nil なら予約なし」の 1 文だけをプロパティに残す。2 は `isReviewDisplay` のような 1 行ヘルパーへ抽出するか、条件を分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `scheduleRebuild` の doc コメントに、まとめ方の根拠（実測）と「その時点の `lastListing` を読む」不変条件が書かれ、`pendingRebuild` の doc は予約状態の説明だけになっている
- [ ] #2 `revealChangedFolders` に多行の `guard` 条件が無く、`/swiftlint-baseline` で main との差分がゼロ
<!-- AC:END -->
