---
id: TASK-210
title: UserDefaults パス配列ストア 3 実装の共通基盤化(PathListDefaults)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:56'
updated_date: '2026-07-31 07:24'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/SessionStore.swift
  - BefoldApp/BefoldKit/BookmarkStore.swift
  - BefoldApp/befold/App/RecentDocumentsStore.swift
priority: low
ordinal: 290000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「stringArray(forKey:) ?? [] → normalizedPathKey で操作 → set(_:forKey:)」のボイラープレートが SessionStore(noteOpened/savedPaths)・BookmarkStore(add/savedPaths/save)・RecentDocumentsStore(noteOpened/savedPaths/save)の 3 クラスで重複している。BookmarkStore.add は SessionStore.noteOpened と 1 行単位で同一のアルゴリズム。noteRenamed(旧キー除去/置換 → 保存)も各所で変奏。BefoldKit に PathListDefaults(paths/appendIfAbsent/moveToFront/remove/replace)のようなプリミティブを置いて 3 ストアが合成する形にし、normalizedPathKey の使い方と永続化順序を揃え、新ストア追加時の rename 反映漏れを防ぐ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 パス配列の load/save/追加/rename プリミティブが共通実装に統合され、3 ストアがそれを合成する
- [x] #2 各ストアのドメイン API(freeze・seedIfNeeded 等)と既存挙動が変わらない(既存テストが通る)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に PathListDefaults を新設(paths/urls/contains/hasStoredValue/replaceAll/appendIfAbsent/moveToFront/remove/toggle/replace、任意の limit)
2. PathListDefaultsTests を先に書く(TDD)
3. SessionStore(savedPaths/noteOpened/noteClosed)を PathListDefaults の合成に置き換える
4. BookmarkStore(savedPaths/add/toggle/noteRenamed/save)を置き換える
5. RecentDocumentsStore(savedPaths/noteOpened/noteRenamed/clear/seedIfNeeded/save)を置き換える(limit=maximumCount)
6. swift build && swift test で既存挙動維持を確認
7. project.yml / Package.swift はディレクトリ単位指定のため変更不要であることを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BefoldKit/PathListDefaults.swift を新設(paths/urls/hasStoredValue/contains/replaceAll/appendIfAbsent/moveToFront/remove/toggle/replace、任意 limit)。SessionStore(savedURLs/noteOpened/noteClosed)・BookmarkStore(isBookmarked/add/toggle/bookmarkedURLs/noteRenamed)・RecentDocumentsStore(recentURLs/noteOpened/noteRenamed/clear/seedIfNeeded)を合成に置き換え、各ストアの private savedPaths/save は削除。RecentDocumentsStore の上限は PathListDefaults(limit:)、seedIfNeeded の初回判定は hasStoredValue で表現。project.yml / Package.swift はディレクトリ単位でソースを取り込むため変更不要。検証: swift build 成功、swift test --filter 'PathListDefaultsTests|BookmarkStoreTests|RecentDocumentsStoreTests|SessionStoreTests|SessionRestorerTests|BookmarksMenuControllerTests|RecentDocumentsMenuControllerTests|CLIBookmarkCommandTests' で 69 tests / 8 suites 全通過。フルスイートは本変更前後いずれも GUI/分散系のフレーク(ViewerWindowControllerToolbarTests / DistributedAckWaiterIntegrationTests)で 1-2 件失敗し、本変更とは無関係。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
UserDefaults のパス配列ボイラープレートを BefoldKit の PathListDefaults に集約し、SessionStore / BookmarkStore / RecentDocumentsStore がそれを合成する形にした。ドメイン API(freeze / seedIfNeeded / 上限プルーニング)と既存挙動は維持。PathListDefaultsTests を新規追加し、既存ストア系テスト 69 件と併せて全通過を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
