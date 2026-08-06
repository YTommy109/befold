---
id: TASK-343
title: GitDiffLoaderTests の CountingDiffReader を共有の RecordingDiffReader へ統合する
status: Done
assignee: []
created_date: '2026-08-06 05:36'
updated_date: '2026-08-06 06:46'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 609000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

GitDiffLoaderTests.swift:7 の private CountingDiffReader は、同ブランチで追加した共有スタブ RecordingDiffReader（DiffTestSupport.swift:20）と実質同一（NSLock・呼び出しカウンタ・固定結果・任意の Thread.sleep 遅延）で、同じ befoldTests ターゲット内の重複。GitDiffReading の変更（引数追加や async 化）を二重に適用する必要があり、片方だけ修正されて挙動が乖離し得る。

GitDiffLoaderTests が RecordingDiffReader を直接使えば CountingDiffReader は削除できる。併せて ViewerWindowControllerDiffTests.swift:33 の RecordingDiffToggleDelegate（空スタブ 6 個 + 記録）にも同型の重複がないか確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitDiffLoaderTests が RecordingDiffReader を使い、CountingDiffReader が削除されている
- [x] #2 既存テストが引き続き通る
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitDiffLoaderTests の private CountingDiffReader を削除し、共有スタブ RecordingDiffReader(DiffTestSupport.swift)へ統合した(.calls → .callCount)。同型の重複として指摘された ViewerWindowControllerDiffTests.RecordingDiffToggleDelegate も削除し、既存の MockViewerWindowControllerDelegate を befoldTests 内で共有する形へ寄せた(Bool フラグを回数カウンタ toggleSourceDiffCallCount に変更)。swift test --skip Integration --skip FileWatcherTests で 1078 テスト green。
<!-- SECTION:FINAL_SUMMARY:END -->
