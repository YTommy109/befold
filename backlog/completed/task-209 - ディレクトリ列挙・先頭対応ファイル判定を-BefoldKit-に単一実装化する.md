---
id: TASK-209
title: ディレクトリ列挙・先頭対応ファイル判定を BefoldKit に単一実装化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:55'
updated_date: '2026-07-31 07:29'
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
- [x] #1 ディレクトリ列挙+ソートの実装が BefoldKit の 1 箇所に統合され、SupportedFileResolver と DirectoryLister が委譲する
- [x] #2 先頭対応ファイルの選択ロジックが単一実装になり、DirectoryLister.firstSupportedFile の複製が消える
- [x] #3 CLI --check と GUI サイドバーの既存挙動が変わらない(既存テストが通る)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に DirectoryEnumeration を新設し、contentsOfDirectory(skipsHiddenFiles 切替) → isDirectory 分類 → localizedStandardCompare 昇順ソートの単一実装を置く
2. 先頭対応ファイル判定(firstSupportedFile / resolveFileToOpen の選択)も DirectoryEnumeration に集約する
3. SupportedFileResolver.sortedFiles を削除し DirectoryEnumeration へ委譲
4. DirectoryLister.sortedContents / firstSupportedFile を DirectoryEnumeration へ委譲
5. DirectoryEnumeration のテストを追加し、既存の DirectoryLister / CLI --check テストが通ることを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BefoldKit/DirectoryEnumeration.swift を新設し、contentsOfDirectory→isDirectory 分類→localizedStandardCompare 昇順ソートの単一実装と firstSupportedFile / fileToOpen(選択規則)を集約。SupportedFileResolver.sortedFiles と DirectoryLister.sortedContents / firstSupportedFile / private sortedByFileName の複製を削除して委譲に置換。[URL].sortedByFileName() を BefoldKit の public 拡張にし allEntriesSorted もそれを使う。project.yml / Package.swift はソースをディレクトリ glob で拾うため変更不要。検証: swift test 全 912 テスト成功(新規 DirectoryEnumerationTests 7 件含む。CLI --check の CLICheckAndBookmarkDefaultsTests、GUI サイドバーの DirectoryListerTests も既存のまま通過)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ディレクトリ列挙・ソートと先頭対応ファイル判定を BefoldKit.DirectoryEnumeration に単一実装化し、SupportedFileResolver と DirectoryLister を委譲に変更。挙動不変は既存の DirectoryListerTests / CLICheckAndBookmarkDefaultsTests を含む swift test 全 912 テスト成功で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
