---
id: TASK-126
title: makeIsolatedDefaults がテスト実行ごとに orphan plist を漏らす
status: To Do
assignee: []
created_date: '2026-07-24 22:22'
labels:
  - test
  - bug
dependencies: []
priority: medium
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。BefoldTestSupport/IsolatedDefaults.swift:9 の makeIsolatedDefaults は呼び出しごとに一意な永続 UserDefaults ドメイン("<prefix>-<UUID>")を作るが、テスト後に削除しない。removePersistentDomain は作成時にのみ呼ばれ、新規ランダム名に対しては no-op。
swift test 1 回ごとに数十個の orphan plist(例: CLIBookmarkCommandTests-3F2A...plist)が ~/Library/Preferences に堆積し、開発を続けるほど cfprefsd を劣化させる。クリーンアップ経路がない。既に 8 万個以上の堆積が確認されている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テスト終了時に作成した UserDefaults ドメインの plist が削除される(deinit/teardown 等の仕組み)
- [ ] #2 既存の堆積 plist を掃除する手段(スクリプトまたは初回実行時掃除)を提供する
<!-- AC:END -->
