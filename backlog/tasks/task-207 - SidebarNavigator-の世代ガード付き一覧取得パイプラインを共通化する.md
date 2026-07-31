---
id: TASK-207
title: SidebarNavigator の世代ガード付き一覧取得パイプラインを共通化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:52'
updated_date: '2026-07-31 07:21'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/SidebarNavigator.swift
priority: medium
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
refreshFileList(SidebarNavigator.swift:117-145)と navigateToFolder(同 192-217)が「refreshBaseDirectory → syncShowHiddenFiles → sortOrder 取得 → listingGeneration += 1 → Task { entries 取得; 世代・host guard; 反映 }」という同一パイプラインを二重に持つ。違いはディレクトリの確定方法と完了後の選択ロジックのみ。世代ガード・host guard という競合安全性の要が 2 箇所に散っており、guard の書き方が既に揺れ始めている(let host = self.host と self.host != nil)。ディレクトリを引数で受ける performListing(of:onApplied:) の形に抽出すれば順序は不変。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 世代ガード付きの一覧取得が単一のヘルパーに統合され、refreshFileList と navigateToFolder がそれを使う
- [x] #2 一覧更新の競合時(連続操作・フォルダ移動中の再読み込み)の挙動が現状と変わらない(既存テストが通る)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. refreshFileList / navigateToFolder の共通部分(refreshBaseDirectory → syncShowHiddenFiles → sortOrder 取得 → listingGeneration += 1 → Task { 列挙; 世代・host guard })を performListing(of:onApplied:) に抽出する
2. onApplied は (host, entries) を受け、各呼び出し側で entries 反映と選択ロジックのみを担う
3. guard は let host = self.host に統一する
4. 既存テスト(SidebarNavigatorIntegrationTests の世代競合テスト等)で挙動不変を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
performListing(of:onApplied:) を新設し、refreshBaseDirectory → syncShowHiddenFiles → sortOrder 取得 → listingGeneration += 1 → Task { 列挙; 世代・host guard } を一元化。onApplied は (host, entries) を受け、entries 反映と選択ロジックのみを担う。guard は let host = self.host に統一(navigateToFolder 側は host 未使用のため _ で受ける)。順序は不変。検証: swift build 成功、swift test --filter Sidebar (30 tests)、--filter ViewerWindowController (53 tests) がパス。フルスイートでは FileWatcherIntegrationTests.detectsAtomicSave が並列負荷下で不安定に失敗するが、単独実行では変更前後とも成功する既知の flaky で本変更とは無関係。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator の refreshFileList / navigateToFolder に重複していた世代ガード付き一覧取得パイプラインを performListing(of:onApplied:) へ抽出し、host guard の書き方も統一した。既存の世代競合テスト(連続 navigateToFolder / フォルダ選択保持)を含む Sidebar 30 tests・ViewerWindowController 53 tests のパスで挙動不変を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
