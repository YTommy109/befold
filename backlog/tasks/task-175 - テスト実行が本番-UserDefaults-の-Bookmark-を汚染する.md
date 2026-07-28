---
id: TASK-175
title: テスト実行が本番 UserDefaults の Bookmark を汚染する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 00:45'
updated_date: '2026-07-28 01:37'
labels:
  - test
  - bookmark
dependencies: []
priority: high
type: bug
ordinal: 250000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テスト実行後に実アプリのブックマークが汚染される。Bookmark は BookmarkStore が UserDefaults のキー "BookmarkedPaths"(suite=本番アプリ識別子)に永続化する。ViewerWindowManager / ViewerWindowController / AppDelegate の bookmarkStore 既定引数が BookmarkStore()(= .standard)のため、テストがこれらを注入なしで生成する経路があると本番 UserDefaults に書き込み、実ブックマークを汚染する。加えて befoldTests/ViewerRendererMessageHandlingTests.swift:320-321 は UserDefaults(suiteName: UUID) で永続ドメインを生成しており、BefoldTestSupport/IsolatedDefaults.swift が戒める ~/Library/Preferences への plist 残留パターンに該当する。テストが作成した bookmark(および永続 defaults)は本番領域を触らず、実行後に残さないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テストスイート実行後、本番 UserDefaults(BookmarkedPaths)および ~/Library/Preferences に、テスト起因のブックマーク/plist が残らない
- [x] #2 BookmarkStore に触れる全テスト経路が makeIsolatedDefaults 等の隔離済み defaults を使い、.standard へ到達しない(既定引数 .standard へのフォールバックをテストが踏まないことを保証する)
- [x] #3 ViewerRendererMessageHandlingTests の永続 suiteName 生成を廃し、メモリ隔離 defaults に置き換える
- [x] #4 汚染源をテストで検知できる回帰ガード(例: 実行前後で本番 BookmarkedPaths が不変であることの検証)を設ける
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 本番コードの既定引数 .standard を排除し bookmarkStore/defaults を注入必須化する:
   - BookmarkStore.init(defaults:) の既定 .standard を削除
   - ViewerWindowManager / ViewerWindowController の bookmarkStore 既定引数 BookmarkStore() を削除
2. 本番生成箇所を明示注入に修正:
   - AppDelegate: BookmarkStore(defaults: .standard) を生成し ViewerWindowManager/Controller へ渡す
3. ビルドで炙り出される全テストの未注入をコンパイルエラーで検出→隔離 defaults(makeIsolatedDefaults)由来の BookmarkStore を注入:
   ViewerWindowManagerIntegrationTests / ViewerWindowManagerDisplayOverridesIntegrationTests / ViewerWindowControllerCLIOptionsTests / ViewerWindowControllerSourceModeTests / SidebarNavigatorIntegrationTests
4. ViewerRendererMessageHandlingTests.ephemeralDefaults を makeIsolatedDefaults へ置換 (AC#3)
5. 回帰ガードテスト追加: 本番 standard の BookmarkedPaths がテストで不変であることを検証 (AC#4)
6. swift test で全緑を確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 全 801 テスト緑。修正後フルスイート実行後 ~/Library/Preferences の ViewerRenderer plist=0(2168→0)、本番 com.degino.befold BookmarkedPaths の temp 由来=0(77→0)。対象テストのみ再実行で plist 増加なし(2168→2168 当時→現0)、BefoldCLICommandTests 再実行で本番 bookmark 増加なし(73→73)を実測。
実装: (1)BookmarkStore.init/ViewerWindowManager/ViewerWindowController の既定 .standard/BookmarkStore() を排除し bookmarkStore 注入を必須化(型でフォールバックを封鎖=AC#2)。本番は AppDelegate が BookmarkStore(defaults:.standard) を明示注入。(2)漏れていた5テスト経路(+ControllerTests直呼び等)へ隔離 defaults 由来 BookmarkStore を注入。(3)ViewerRendererMessageHandlingTests.ephemeralDefaults を makeIsolatedDefaults へ置換(AC#3)。(4)BookmarkStoreTests に回帰ガード isolatedBookmarkOperationsDoNotTouchProductionStandard を追加(AC#4)。(5)clean-test-defaults.sh がドット区切り<prefix>.<UUID>.plist を取りこぼす穴を修正(接頭辞にドットを含まない条件で逆DNS実在ドメインは除外)し、堆積 2168 件と本番 temp bookmark を掃除。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BookmarkStore/ViewerWindowManager/ViewerWindowController の既定引数 .standard を排除し bookmarkStore 注入を必須化することで、テストが本番 UserDefaults へフォールバックする経路を型レベルで封鎖。未注入だったテスト経路へ隔離 defaults を注入、ViewerRendererMessageHandlingTests の永続 suite 生成を makeIsolatedDefaults へ置換、回帰ガードテストを追加。clean-test-defaults.sh のドット区切り取りこぼしを修正し堆積残留(plist 2168件・本番temp bookmark 77件)を掃除。swift test 801件緑、修正後フルスイート実行で残留ゼロを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
