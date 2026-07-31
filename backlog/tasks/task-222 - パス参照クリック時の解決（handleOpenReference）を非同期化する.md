---
id: TASK-222
title: パス参照クリック時の解決（handleOpenReference）を非同期化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:13'
updated_date: '2026-07-31 09:42'
labels:
  - refactor
  - performance
dependencies: []
priority: high
type: task
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ReferenceResolutionCoordinator.handleOpenReference (befold/App/ReferenceResolutionCoordinator.swift:53-69) が TrackedPathResolver.resolve を MainActor 上で同期実行している。キャッシュ未命中時は共有ロック + git ls-files subprocess + SuffixPathIndex 構築を待つ。同ファイル :75-77 に「MainActor 上では走らせない」と明記されているのに resolveReferences だけ Task.detached で、クリック経路は同期のまま。warm 完了前のクリックや別リポジトリのウィンドウがロック保持中の場合に UI が停止する。resolveReferences と同じ形（解決を Task.detached、openReference / presentReferenceNotFound は MainActor に戻す）に揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 参照クリック時に MainActor 上で git subprocess・ロック待ちが発生しない
- [x] #2 解決成功時のオープン・失敗時の not found 表示が従来どおり動作する
- [x] #3 非同期化後の解決経路にユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ReferenceResolutionCoordinator.handleOpenReference を resolveReferences と同じ方針(resolver/baseURL を捕捉→ Task { Task.detached { resolver.resolve(...) }.value; host への通知は MainActor に戻る })に変更する
2. テストから完了を待てるよう pendingOpenReferenceTask: Task<Void, Never>? を公開する(SidebarNavigator.pendingBaseDirectoryTask と同じシーム)
3. handleOpenReference を同期呼び出し直後に副作用を assert していた既存テスト3件を async化し、pendingOpenReferenceTask?.value を await するよう修正する
4. クリック時解決が MainActor を離れて git 索引にアクセスすることを検証する新規テストを追加する(resolveReferencesTouchesGitIndexOffMainThread と対になるテスト)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
handleOpenReference を resolveReferences と同じ Task.detached パターンに変更。既存の同期呼び出し前提テスト(handleOpenReferenceRecordsHistoryAndBackRestores / resolveReferencesAndOpenReferenceAgreeOnGitFallback / handleOpenReferenceWithNewWindowLeavesOriginalWindowUnchanged)は async 化し pendingOpenReferenceTask?.value を await するよう修正(先に実行してレースで3件failさせてから修正、原因は想定通り)。新規に handleOpenReferenceTouchesGitIndexOffMainThread を追加し、クリック時解決が MainActor を離れて git 索引にアクセスすることをスレッド観測で固定。swift build / swift test --skip Integration --skip FileWatcherTests は 881 件全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ReferenceResolutionCoordinator.handleOpenReference を resolveReferences と同じ非同期パターンに揃えた: resolver/baseURL を捕捉し Task { let reference = await Task.detached { resolver.resolve(...) }.value; host への openReference/presentReferenceNotFound 通知だけ MainActor に戻す }。テストが完了を待てるよう pendingOpenReferenceTask を公開(SidebarNavigator.pendingBaseDirectoryTask と同じシーム)。クリック時に MainActor 上で git subprocess・ロック待ちは発生しない。検証: 既存の同期前提テスト3件を async化してレースを解消、新規にクリック時解決のスレッド観測テスト(handleOpenReferenceTouchesGitIndexOffMainThread)を追加、swift build 成功、swift test --skip Integration --skip FileWatcherTests で 881 件全て成功。
<!-- SECTION:FINAL_SUMMARY:END -->
