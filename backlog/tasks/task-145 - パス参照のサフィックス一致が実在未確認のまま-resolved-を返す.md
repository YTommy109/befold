---
id: TASK-145
title: パス参照のサフィックス一致が実在未確認のまま resolved を返す
status: In Progress
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 11:38'
labels:
  - path-reference
dependencies: []
priority: high
type: bug
ordinal: 205000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TrackedPathResolver のサフィックス一致経路（TrackedPathResolver.swift L56-60）は SuffixPathMatcher.bestMatch の結果を実在確認なしで .resolved として返す。`git ls-files` は (1) worktree から削除済みで index にだけ残るファイル、(2) submodule の gitlink エントリ（実体はディレクトリ）も列挙するため、存在しないファイル等がリンク化され「クリックしても開けないリンク」が生じる。`.resolved` の /// は「実在を確認できたローカルファイル」と断定しており実装と不一致（feat/document_path のコードレビュー指摘・重大）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bestMatch 成立後に fileReader.isExistingFile による実在確認を挟み、不成立なら .unresolved を返す
- [ ] #2 「追跡されているが worktree に実在しないファイル」の回帰テストを TrackedPathResolverTests に追加する
- [ ] #3 .resolved の /// コメントと実装の整合が取れている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TrackedPathResolver.resolve のサフィックス一致経路で bestMatch 成立後に fileReader.isExistingFile を挟み、不成立なら .unresolved を返す
2. 既存テスト resolvesViaGitSuffix / resolvesWithLineSuffix は existing: [] のまま .resolved を期待しているため、追跡ファイルを existing に加えて実態に合わせる
3. 「git が追跡しているが worktree に実在しない(削除済み・submodule gitlink)」の回帰テストを追加する
4. .resolved の /// 「実在を確認できたローカルファイル」は実装が追いつく形になるため文言は維持する
<!-- SECTION:PLAN:END -->
