---
id: TASK-256
title: SidebarNavigator の残る Integration テスト 2 件を unit へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 23:03'
updated_date: '2026-08-02 00:25'
labels: []
dependencies: []
priority: low
type: task
ordinal: 452600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-246 のレビューで、SidebarNavigatorIntegrationTests に残った 2 件が実 FS を本質としないと判明した。
- :62 navigatingUpUpdatesRootDirectory が検証する updateRootDirectory(SidebarNavigator.swift:230-239)はパス文字列の純粋比較で FS を触らない
- :93 refreshFileListPreservesFolderSelection は refreshFileList の選択保持ポリシー(SidebarNavigator.swift:131-136)で、TASK-246 で移設した 6 件と同性質
実 FS が本質なのは symlink テスト(:25)のみというのが実態。TASK-246 と同じ directoryLister スタブ方式で unit へ移す。
注意: TASK-246 のレビューで「移設によって元のテストが固定していた不変条件が失われる」事例が 2 件見つかっている。移設時は元テストが何を固定していたかを列挙し、新テストで同じ強度が保たれることを確認すること。
価値は実行時間ではなくテスト分類の正確さ(対象スイートは全体時間にほぼ寄与しない)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対象 2 件が directoryLister スタブによる unit テストへ移行する
- [x] #2 Integration 側には実 FS が本質のテスト(symlink 解決)のみが残る
- [x] #3 移設前後で検証している不変条件が同じ強度で保たれている
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarNavigatorIntegrationTests の navigatingUpUpdatesRootDirectory / refreshFileListPreservesFolderSelection が固定していた不変条件を列挙
2. TASK-246と同じdirectoryListerスタブ方式でSidebarNavigatorFolderNavigationTestsへ移設
3. Integration側のdocstringをsymlinkテストのみ残る旨に更新
4. mutation testingで新テストが検証対象ロジックの破壊を検知するか確認
5. swift test を3回連続グリーンで確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-246 のレビューで Minor として挙がっていた「Integration に残った 2 件も実 FS が本質ではない」への対応。移設後、SidebarNavigatorIntegrationTests に残るのは symlink 解決の 1 本のみとなった。
実装者が mutation testing を実施し、検証対象ロジック(updateRootDirectory の guard、refreshFileList の selectionStillValid)を壊すと確実に落ちることを確認(確認後に復元)。レビューでもコードから同じ結論が裏付けられ、TASK-246 で起きた「移設で不変条件が空振りになる」事故には該当しないと確認された。特に refreshFileList 側は ensureCurrentFile が host.currentFileURL を entries に足す挙動まで含めて元テストと同じ条件を再現できている。
TASK-252 で規約化した予防手順(不変条件の列挙 → 照合 → 可能なら変異テスト)が実際に運用された最初の事例。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator の Integration に残っていた 2 件(navigatingUpUpdatesRootDirectory / refreshFileListPreservesFolderSelection)を、TASK-246 で作った directoryLister スタブ + 共有 StubHost の流儀で unit へ移した。Integration 側には実 FS が本質の symlink 解決テストのみが残る。
移設前後で assertion は 1:1 で保持され、mutation testing で検証対象ロジックを壊すと落ちることを確認済み。
検証: swift test 951 tests / 142 suites グリーン(フル 3 回連続)。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
