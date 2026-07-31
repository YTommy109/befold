---
id: TASK-210
title: UserDefaults パス配列ストア 3 実装の共通基盤化(PathListDefaults)
status: To Do
assignee: []
created_date: '2026-07-31 02:56'
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
- [ ] #1 パス配列の load/save/追加/rename プリミティブが共通実装に統合され、3 ストアがそれを合成する
- [ ] #2 各ストアのドメイン API(freeze・seedIfNeeded 等)と既存挙動が変わらない(既存テストが通る)
<!-- AC:END -->
