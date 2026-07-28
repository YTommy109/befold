---
id: TASK-175
title: テスト実行が本番 UserDefaults の Bookmark を汚染する
status: To Do
assignee: []
created_date: '2026-07-28 00:45'
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
- [ ] #1 テストスイート実行後、本番 UserDefaults(BookmarkedPaths)および ~/Library/Preferences に、テスト起因のブックマーク/plist が残らない
- [ ] #2 BookmarkStore に触れる全テスト経路が makeIsolatedDefaults 等の隔離済み defaults を使い、.standard へ到達しない(既定引数 .standard へのフォールバックをテストが踏まないことを保証する)
- [ ] #3 ViewerRendererMessageHandlingTests の永続 suiteName 生成を廃し、メモリ隔離 defaults に置き換える
- [ ] #4 汚染源をテストで検知できる回帰ガード(例: 実行前後で本番 BookmarkedPaths が不変であることの検証)を設ける
<!-- AC:END -->
