---
id: TASK-209
title: ディレクトリ列挙・先頭対応ファイル判定を BefoldKit に単一実装化する
status: To Do
assignee: []
created_date: '2026-07-31 02:55'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/BefoldKit/SupportedFileResolver.swift
  - BefoldApp/befold/Viewer/DirectoryLister.swift
priority: medium
ordinal: 289000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「contentsOfDirectory(skipsHiddenFiles) → fileReader.isDirectory で分類/フィルタ → localizedStandardCompare 昇順ソート」が SupportedFileResolver.sortedFiles(BefoldKit/SupportedFileResolver.swift:17-24)と DirectoryLister.sortedContents(befold/Viewer/DirectoryLister.swift:116-143)で二重実装されている(ダングリングシンボリックリンクの扱いのコメントまで複製)。DirectoryLister.firstSupportedFile も SupportedFileResolver.resolveFileToOpen の選択ロジックの複製。CLI --check と GUI サイドバーで「フォルダを開いたとき最初に開くファイル」の判定がドリフトする芽であり、CLICheckCommand の「判定を独自に持つと必ず GUI とドリフトする」という設計方針にも反する。BefoldKit に列挙の単一実装元(例: DirectoryEnumeration.sortedContents)を置き、両者を委譲させる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ディレクトリ列挙+ソートの実装が BefoldKit の 1 箇所に統合され、SupportedFileResolver と DirectoryLister が委譲する
- [ ] #2 先頭対応ファイルの選択ロジックが単一実装になり、DirectoryLister.firstSupportedFile の複製が消える
- [ ] #3 CLI --check と GUI サイドバーの既存挙動が変わらない(既存テストが通る)
<!-- AC:END -->
