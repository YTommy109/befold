---
id: TASK-290
title: 絞り込み関連テストのフィクスチャと前提を実態に合わせる
status: Done
assignee: []
created_date: '2026-08-04 07:29'
updated_date: '2026-08-04 09:20'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 480000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)のテスト品質指摘 2 件。

1. FileListModelFilterTests: 新しい絞り込みテストが gitStatuses だけを設定し gitFolderStatuses を空にしているが、SidebarNavigator は常に同じ aggregate 呼び出しから両方を代入するため、この組み合わせは本番で発生しない。結果として本番では到達しない分岐を固定してしまい、gitFolderStatuses 経路の退行は緑のまま通る。フィクスチャは GitFolderStatus.aggregate(statuses:) 経由で組む。
2. SidebarDisplayPreferenceTests: showChangedFilesOnly の永続化テスト 2 件が既定イニシャライザで読み戻しており、注入引数ではなく周囲の FeatureGate 値（DEBUG かどうか）に依存する。swift test -c release などでは永続化とは無関係の理由で落ちる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 絞り込みテストのフィクスチャが GitFolderStatus.aggregate 経由で組まれ、本番で起きうる状態だけを固定する
- [x] #2 永続化テストが FeatureGate の周囲の値に依存せず、注入引数で意図した状態を作る
- [x] #3 swift test -c release で該当テストが通ることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1 は着手時点で既に満たされていた: FileListModelFilterTests の applyGitStatus が SidebarGitStatus(directoryKey:statuses:) を通しており、その init が GitFolderStatus.aggregate(statuses:) で folders を作る(commit 9c348044 の SidebarGitStatus 導入による)。gitStatuses / gitFolderStatuses を個別に設定する経路はもう存在しない。AC#2 のみ修正: SidebarDisplayPreferenceTests に makePreference(defaults:available:) を追加し、永続化系 2 件(changedFilesOnlyPersistsAcrossInstances / settingsArePersistedIndependently)と既定値テストの読み戻しで isChangedFilesOnlyAvailable を明示注入した。修正前後を release 構成で実測: 修正前は swift test -c release で上記 2 件が failed(FeatureGate 由来で読み戻しが false)、修正後は 20 tests(2 suites)全通過。swiftlint は当該ファイル 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
永続化テストの読み戻しを isChangedFilesOnlyAvailable の明示注入に変え、FeatureGate(DEBUG か否か)への依存を外した。AC#1 のフィクスチャは SidebarGitStatus 導入により既に GitFolderStatus.aggregate 経由。swift test -c release で修正前 2 件 failed → 修正後 20 tests 全通過を実測。
<!-- SECTION:FINAL_SUMMARY:END -->
