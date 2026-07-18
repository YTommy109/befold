---
id: TASK-1.5
title: ViewerWindowController の減量と依存注入（ViewerStore/DirectoryLister 注入、ツールバー・スワイプ抽出）
status: To Do
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 13:40'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/213
parent_task_id: TASK-1
priority: medium
ordinal: 1700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
【2026-07-18 再評価】QuickLook 対応の前提ではない。appex はウィンドウを持たず ViewerWindowController を一切使わない（appex は preparePreviewOfFile で WKWebView を1枚返すだけ）ため、QuickLook 対応から切り離して後回し可。アプリ内部品質の改善として独立に扱う。

GitHub Issue #213 から移行。ViewerWindowController（812行、out_degree 46）に7責務が同居。ツールバーとスワイプ検知を独立クラスへ抽出し、ViewerStore と DirectoryLister を init 注入に変え、AppDelegate.shared?.openViewer を注入クロージャ化する。isSourceMode の二重保持とツールバー検索の重複も解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツールバーとスワイプ検知が独立クラスに抽出されている
- [ ] #2 ViewerStore と DirectoryLister が init 注入されている
- [ ] #3 AppDelegate.shared?.openViewer が注入クロージャ化されている
- [ ] #4 isSourceMode の二重保持が解消されている
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
<!-- SECTION:NOTES:END -->
