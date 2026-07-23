---
id: TASK-111
title: 'CLI ブックマーク: パス正規化が GUI と不一致、定数も重複'
status: Done
assignee: []
created_date: '2026-07-23 12:19'
updated_date: '2026-07-23 13:04'
labels:
  - bug
  - cli
dependencies:
  - TASK-115
priority: medium
ordinal: 50500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIBookmarkDefaults は standardizedFileURL.path でパスを正規化するが、GUI の BookmarkStore は resolvingSymlinksInPath().path を使用する。シンボリックリンク経由のパスで CLI と GUI のブックマークが一致しない。また UserDefaults キーとスイート名がハードコードされており BookmarkStore との重複がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI と GUI のパス正規化ロジックが統一されている
- [x] #2 シンボリックリンク経由のブックマーク登録・参照テストが存在する
- [x] #3 UserDefaults のブックマークキー・スイート名の重複が解消されている(BookmarkStore の一本化によりキー定義自体が単一になった)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-115(BefoldKit への共通ロジック移設)で解消する方針。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-115 で CLIBookmarkDefaults を削除し、GUI と同じ BookmarkStore(BefoldKit へ移設、normalizedPathKey で symlink 解決)を CLI からも使うよう統一した。キー・スイート名の重複は BookmarkStore 一本化により定義自体が単一になり解消。検証: befoldTests/BookmarkStoreTests.swift の addResolvesSymlinkToRealPath、befoldCLITests/CLICheckAndBookmarkDefaultsTests.swift の bookmarkResolvesSymlinkToRealPath、swift test 全体(601 tests green)。
<!-- SECTION:FINAL_SUMMARY:END -->
