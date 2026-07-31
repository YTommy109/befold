---
id: TASK-225
title: サイドバー一覧反映後の normalizedPathKey 一斉評価を列挙時の事前計算に置き換える
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-07-31 12:31'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator.swift の onApplied（MainActor）内で entries.contains { $0.url.normalizedPathKey == key } のような突き合わせが複数箇所（:132,:174,:186,:194,:216,:298）あり、normalizedPathKey は resolvingSymlinksInPath の syscall なのでエントリ数ぶんの stat が MainActor で走る。列挙自体はメイン外へ逃がしたのに突き合わせだけ残っている。FileListEntry に列挙時（メイン外）に解決済みの pathKey を持たせるか、突き合わせ用 Set を listEntriesAsync の戻り値に含める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 一覧反映後の pathKey 突き合わせで MainActor 上の syscall がエントリ数に比例しない
- [x] #2 選択維持・ルート更新などの既存挙動が維持されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListEntry.swift: pathKey: String フィールドを追加し、init で url.normalizedPathKey を構築時に計算(DirectoryLister.buildEntries はメイン外実行のため、フォルダー/ファイル/親ナビゲーションの列挙時点で stat がメイン外になる)。既存の containsSupportedFile と同じ事前計算パターン。
2. SidebarNavigator.swift: entries.contains/first の4箇所(selectionStillValid, ensureCurrentFile, folderEntryURL, matchingEntryURL)を $0.url.normalizedPathKey == key から $0.pathKey == key に置き換え。比較対象の key 側(selection/currentFile/url 単体)は従来どおり1回だけの計算のため変更不要。
3. FileListEntryTests に pathKey が url.normalizedPathKey と一致することを検証するテストを追加。
4. 既存の SidebarNavigatorIntegrationTests(選択維持等)が無変更で通ることで、突き合わせロジックの外部挙動が同一であることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 886件全通過(Integration/FileWatcherTests除く)。SwiftLint 実行、変更ファイルに新規違反なし。FileListEntry.pathKey を DirectoryLister.buildEntries(メイン外 async)構築時に事前計算し、SidebarNavigator の4箇所の突き合わせをこのフィールド参照に置き換えたことで、一覧反映後の MainActor 上の stat 呼び出しがエントリ数ぶん発生しなくなった(SidebarNavigator.ensureCurrentFile の単発合成エントリのみ1回の stat が残るが、エントリ数に比例しない)。既存の選択維持テスト(SidebarNavigatorIntegrationTests)が無変更で通過し、外部挙動が同一であることを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListEntry に pathKey(url.normalizedPathKey の事前計算値)を追加し、DirectoryLister.buildEntries(既にメイン外 async)の列挙時点で計算されるようにした。SidebarNavigator の selectionStillValid/ensureCurrentFile/folderEntryURL/matchingEntryURL の4箇所で、entries.contains/first の突き合わせを $0.url.normalizedPathKey (resolvingSymlinksInPath syscall) から $0.pathKey 参照へ置き換え、一覧反映後の MainActor 上の stat がエントリ数に比例しないようにした。swift test 886件全通過(新規1件含む)で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
