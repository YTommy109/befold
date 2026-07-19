---
id: TASK-1.5
title: ViewerWindowController の減量と依存注入（ViewerStore/DirectoryLister 注入、ツールバー・スワイプ抽出）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-19 01:31'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/213
parent_task_id: TASK-1
priority: medium
ordinal: 800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
【2026-07-18 再評価】QuickLook 対応の前提ではない。appex はウィンドウを持たず ViewerWindowController を一切使わない（appex は preparePreviewOfFile で WKWebView を1枚返すだけ）ため、QuickLook 対応から切り離して後回し可。アプリ内部品質の改善として独立に扱う。

GitHub Issue #213 から移行。ViewerWindowController（812行、out_degree 46）に7責務が同居。ツールバーとスワイプ検知を独立クラスへ抽出し、ViewerStore と DirectoryLister を init 注入に変え、AppDelegate.shared?.openViewer を注入クロージャ化する。isSourceMode の二重保持とツールバー検索の重複も解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツールバーとスワイプ検知が独立クラスに抽出されている
- [x] #2 ViewerStore と DirectoryLister が init 注入されている
- [x] #3 AppDelegate.shared?.openViewer が注入クロージャ化されている
- [x] #4 isSourceMode の二重保持が解消されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化方針: isSourceMode は新規状態を増やさず store.isSourceMode への computed property 委譲にする。ツールバー/スワイプ抽出は SidebarNavigator の「Host protocol + weak delegate」パターンを踏襲し新設計は発明しない。

実装順序（各AC独立寄りだがAC#1-bはAC#2/#4のアクセスレベル緩和に依存するため最後）:
1. AC#2: ViewerStore/DirectoryLister を init 注入化（store: ViewerStore = ViewerStore(), directoryLister クロージャ、デフォルト値で無破壊）
2. AC#4: isSourceMode を private(set) var から `var isSourceMode: Bool { store.isSourceMode }` へ変更、applySourceMode の手動同期コード削除
3. AC#3: openFileInNewWindow: (URL) -> Void をinit注入（デフォルト値 AppDelegate.shared?.openViewer(for:)）、ViewerWindowManager.openViewer 内で自己参照クロージャ配線、AppDelegate.swiftは無変更
4. AC#1-a: SwipeHistoryMonitor(新規, BefoldApp/befold/App/) を抽出。NSEvent監視登録/解除とphaseステートマシンを保持、閾値判定は既存SwipeHistoryNavigationのまま利用。handlePhase(_:deltaX:deltaY:)をinternalにしテスト可能にする
5. AC#1-b: ViewerToolbarController(新規, NSObject継承, NSToolbarDelegate準拠) を抽出。ViewerToolbarHost protocol(weak host)経由でViewerWindowControllerに委譲。store/setSourceModeのアクセスレベルをprivate→internalに緩和。toolbar.delegateの設定タイミング(super.init後、window.toolbar代入前)に注意
6. 全体ビルド・テスト・lint確認

テスト方針:
- ViewerWindowControllerToolbarTests.swiftは維持し、呼び出し先をcontroller.toolbarControllerに機械的に書き換え
- SwipeHistoryNavigationTests.swiftは無変更
- 新規 SwipeHistoryMonitorTests.swift を追加（handlePhaseの直接呼び出しでアキュムレータ・閾値判定を検証。start/stopのAppKitランタイム依存部分はユニットテスト対象外）
- ViewerToolbarController単体テストは見送り、既存ToolbarTests経由の統合テストで十分とする
- 既存の6箇所の直接ViewerWindowController(...)呼び出しテストはデフォルト引数依存のため無修正

新規ファイル:
- BefoldApp/befold/App/SwipeHistoryMonitor.swift
- BefoldApp/befold/App/ViewerToolbarController.swift
- BefoldApp/befoldTests/SwipeHistoryMonitorTests.swift

注意点: @MainActor制約、NSToolbarDelegateはNSObject継承必須、weak hostのライフサイクル、SwiftLintのfile_length/type_body_length閾値を最終確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装計画を策定・記録済み(2026-07-18)。ユーザー判断によりいったん保留。着手再開時はbacklogのImplementation Planを参照。

実装計画通りに完了(2026-07-19)。ViewerStore/DirectoryLister/openFileInNewWindowをinit注入化、isSourceModeをstore.isSourceModeへのcomputed property委譲に変更、SwipeHistoryMonitor.swift(NSEvent監視+phaseステートマシン)とViewerToolbarController.swift(NSToolbarDelegate+ViewerToolbarHostパターン)を新規抽出してViewerWindowControllerから分離。ViewerWindowController.swiftは813行→618行に減量。swift build / swift test --skip Integration --skip FileWatcherTests で386テスト全件成功、swiftlint/swiftformat --lint も新規追加ファイルに違反なしを確認。ViewerWindowControllerToolbarTests.swiftはcontroller.toolbarController経由の呼び出しに機械的書き換え、SwipeHistoryMonitorTests.swiftを新規追加(5テスト)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController(813行)からツールバー管理(ViewerToolbarController)とスワイプ検知(SwipeHistoryMonitor)を独立クラスへ抽出し618行に減量。ViewerStore/DirectoryLister/openFileInNewWindowをinit注入化、isSourceModeの二重保持をstore委譲のcomputed propertyに解消。swift build成功、swift test 386件全件成功、swiftlint/swiftformat --lintで新規ファイルに違反なしを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
