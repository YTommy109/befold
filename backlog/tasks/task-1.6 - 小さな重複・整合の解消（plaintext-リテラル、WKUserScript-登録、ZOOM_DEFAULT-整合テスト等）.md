---
id: TASK-1.6
title: 小さな重複・整合の解消（plaintext リテラル、WKUserScript 登録、ZOOM_DEFAULT 整合テスト等）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 11:48'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/214
parent_task_id: TASK-1
priority: low
ordinal: 6600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #214 から移行。アーキテクチャレビューで見つかった低優先の重複・整合課題7項目のまとめ。plaintext リテラルの散在、WKUserScript 登録の定型化、ViewerWindowManager の二重実装、ZOOM_DEFAULT 整合テスト欠落、jest テスト配置不整合、ViewerBridgeTests のリソース参照、デバウンス時間の暗黙結合。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 各重複・整合課題が解消されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileType.swift に static let plaintextFallback を追加し、init 内と ViewerWebView.swift:457 の両方で参照する
2. ViewerWebView.swift の WKUserScript 登録(6回)を配列+ループ化(message handler と同様のパターン)
3. ViewerWindowManager.swift の isOpenInAnotherWindow/focusExistingWindow に共通ヘルパー existingOtherController(for:excluding:) を切り出す
4. ViewerBridgeTests.swift に ZOOM_DEFAULT ⇔ ZoomStore.defaultZoom の照合テストを既存パターンに倣って追加
5. befold/Resources/__tests__/viewer.test.js を BefoldKit/Resources/__tests__/ へ移設し、跨ぎ require を解消。CI (.github/workflows/ci.yml) の jest 実行パスを追従
6. ViewerBridgeTests.swift の resourceURL を #filePath ベースから Bundle.befoldKitResources 経由に変更
7. FileWatcher.swift の debounceDelay デフォルト値を公開定数化し、ViewerStore.swift のコメント/sleep 時間から定数参照するよう変更
各項目実装後に swift build / swift test 相当の確認、jest 移設後は npx jest を実行して検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
7項目すべて実装完了:
1. FileType.plaintextFallback を追加、init と ViewerWebView.swift の重複箇所で参照
2. ViewerWebView.swift の WKUserScript登録6回を配列+ループ化
3. ViewerWindowManager に existingOtherController(for:excluding:) を切り出し、isOpenInAnotherWindow/focusExistingWindow の重複を解消
4. ViewerBridgeTests に zoomDefaultMatchesZoomStore テストを追加(ZOOM_DEFAULT⇔ZoomStore.defaultZoom)
5. jestテストを BefoldKit/Resources/__tests__/ へ移設、require パスを '../viewer' に短縮。project.yml/Package.swift のリソース除外設定も追従
6. ViewerBridgeTests の resourceURL を #filePath ベースから Bundle.befoldKitResources 経由に変更
7. FileWatcher.defaultDebounceDelay を公開定数化し、ViewerStore の fileGoneGracePeriod がそれを参照するよう変更(ハードコード数値コメントを解消)

検証: swift build(警告なし)/ swift test(372件全パス)/ npx jest(197件全パス)/ swiftformat --lint(整形不要)/ xcodegen generate(成功)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitHub Issue #214 由来の7つの低優先重複・整合課題をすべて解消。plaintextリテラル・WKUserScript登録・ViewerWindowManagerの二重実装を共通化し、ZOOM_DEFAULT整合テストとdebounce定数参照を追加、jestテスト配置をBefoldKit/Resources配下に移設した。swift build/test(372件)・npx jest(197件)・swiftformat --lint・xcodegen generate すべて成功で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
