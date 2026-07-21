---
id: TASK-83
title: DirectoryLister がダングリングシンボリックリンク等の非通常エントリをサイレントに一覧から除外する
status: Done
assignee: []
created_date: '2026-07-21 05:46'
updated_date: '2026-07-21 06:09'
labels: []
dependencies: []
references:
  - BefoldApp/befold/Viewer/DirectoryLister.swift
priority: medium
type: bug
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DirectoryLister.sortedContents() の分類ロジックが 'if isDirectory { folders } else { files }' という無条件フォールバックから 'else if fileReader.isExistingFile(at:) { files }' に変わり、isDirectory・isExistingFile のいずれも false となるエントリ（削除済みターゲットを指すシンボリックリンク等）が folders にも files にも入らず、サイレントに一覧から消える。
Finder には見えるのに befold のサイドバー/ファイル一覧には表示されず、そのフォルダが他に開けるファイルを持たない場合は befold check <folder> が『フォルダー内に開けるファイルがありません』という誤った理由を報告する。この非通常エントリのケースを検証するテストが存在しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 isDirectory・isExistingFile が両方 false となるエントリ（ダングリングシンボリックリンク等）が、少なくとも一覧上で存在が分かる形（files への算入、または明示的な警告）で扱われる
- [x] #2 befold check がこのケースで実際の原因（開けないエントリがある）と『フォルダーが空』を区別して報告する
- [x] #3 ダングリングシンボリックリンクを含むフォルダに対する DirectoryLister のテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: バグは commit 2fe57d7 で sortedContents の分類を無条件 else から 'else if isExistingFile' に変えたことによる回帰。専用状態/バケットを増やさず、この else を無条件に戻すのが最小修正(CLAUDE.md の単純化方針に合致)。これで非通常エントリ(ダングリング symlink 等)は files に算入され一覧に出る(AC1)。同時に resolveFileToOpen が nil を返すのは真にファイルの無いフォルダーのみになり、'空' と '開けないエントリあり' が自然に区別できる。
2. CLICheckCommand: resolveFileToOpen が返した target が isExistingFile でない(=実体が無いダングリング symlink)場合に、'空フォルダー' とは別の理由文言で開けないと報告するガードを追加(AC2)。
3. TDD: DirectoryLister にダングリング symlink を含むフォルダーのテスト(listFiles/listEntries)、CLICheckCommand に 'symlink だけのフォルダーは空扱いしない' テストを追加(AC3)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。
【単純化検討の結果】専用バケット/状態を新設せず、sortedContents の分類を回帰前の無条件 else に戻す最小修正を採用(befold/Viewer/DirectoryLister.swift:125-133)。非通常エントリ(ダングリング symlink 等)は files に算入され一覧に出る。
【変更点】
- DirectoryLister.sortedContents: 'else if isExistingFile' を無条件 else に戻し、非通常エントリを files へ算入(AC1)。
- CLICheckCommand.run: resolveFileToOpen の解決先が isExistingFile でない場合に『ファイルの実体が見つかりません(壊れたシンボリックリンクの可能性)』と報告するガードを追加。nil 分岐は『フォルダー内にファイルがありません』に更新し、空フォルダーと壊れたエントリを区別(AC2)。
- テスト追加: DirectoryListerTests に listFilesIncludesDanglingSymlink / listEntriesIncludesDanglingSymlinkAsFile。CLICheckCommandTests に directoryWithOnlyDanglingSymlinkReportsUnopenableEntry、emptyDirectoryFails に文言アサート追加(AC3)。既存 TASK-80 注入テスト(ExclusionFileReader)は分類が isDirectory を参照する新仕様に合わせ、指定名を『ディレクトリ扱い』にする方式へ更新。
【テスト結果】swift test(Integration/FileWatcher 除く)541 tests 全 pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DirectoryLister.sortedContents()の分類を、commit 2fe57d7で導入された'else if isExistingFile'から回帰前の無条件elseに戻し、非通常エントリ(ダングリングシンボリックリンク等)をfilesへ算入するようにした(新規状態/バケットは追加しない単純化方針)。CLICheckCommandには、解決先が実体を持たない場合に「空フォルダー」とは別の理由(壊れたシンボリックリンクの可能性)を報告するガードを追加。検証: DirectoryListerTests/CLICheckCommandTestsに新規テストを追加(ダングリングsymlinkがfilesへ算入されること、checkが空/開けないエントリありを区別して報告すること)、プロジェクト全543テストgreen。
<!-- SECTION:FINAL_SUMMARY:END -->
