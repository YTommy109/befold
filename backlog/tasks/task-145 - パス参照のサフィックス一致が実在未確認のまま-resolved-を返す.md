---
id: TASK-145
title: パス参照のサフィックス一致が実在未確認のまま resolved を返す
status: Done
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 11:44'
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
- [x] #1 bestMatch 成立後に fileReader.isExistingFile による実在確認を挟み、不成立なら .unresolved を返す
- [x] #2 「追跡されているが worktree に実在しないファイル」の回帰テストを TrackedPathResolverTests に追加する
- [x] #3 .resolved の /// コメントと実装の整合が取れている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TrackedPathResolver.resolve のサフィックス一致経路で bestMatch 成立後に fileReader.isExistingFile を挟み、不成立なら .unresolved を返す
2. 既存テスト resolvesViaGitSuffix / resolvesWithLineSuffix は existing: [] のまま .resolved を期待しているため、追跡ファイルを existing に加えて実態に合わせる
3. 「git が追跡しているが worktree に実在しない(削除済み・submodule gitlink)」の回帰テストを追加する
4. .resolved の /// 「実在を確認できたローカルファイル」は実装が追いつく形になるため文言は維持する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TrackedPathResolver のサフィックス一致経路に fileReader.isExistingFile のガードを追加。実在確認は git 一致が成立した href に限られるため、追加 stat は 1 href あたり最大 1 回で解決コストへの影響はない。
既存テスト 4 件（TrackedPathResolverTests の resolvesViaGitSuffix / resolvesWithLineSuffix / resolveAllMatchesSingleResolve、ViewerWindowControllerTests の resolveReferencesReturnsResolvedOnly / resolveReferencesAndOpenReferenceAgreeOnGitFallback）は「一致先が実在しない」前提で .resolved を期待していたため、追跡ファイルを fileReader に登録して実態（書かれた相対位置には無く、追跡先には在る）へ合わせた。
検証: swift test（628 tests, 全パス。修正前は本件の回帰テストを含め 6 issues）、swift build（SwiftLint 込み）、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 追跡ファイルへのサフィックス一致成立後に fileReader.isExistingFile による実在確認を追加し、worktree から削除済み・submodule gitlink 等の「開けないリンク」を unresolved に倒すよう修正した。回帰テスト unresolvedWhenTrackedFileIsMissingFromWorktree を追加し、修正前に落ちること・修正後に全 628 テストが通ることを swift test で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
