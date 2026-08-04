---
id: TASK-79
title: CLI転送の再送で同一requestIDの通知が二重処理されうる
status: Done
assignee: []
created_date: '2026-07-21 00:52'
updated_date: '2026-07-21 01:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward() はACK未受信時に同じ requestID で通知を再送するが、先の試行を取り消さない。受信側の観測が最初の試行のackTimeout(0.5秒)を過ぎた直後に間に合って登録された場合、最初の通知と再送された通知の両方が届き得る。handleCLIOpenRequest はrequestID単位の重複排除を行っていないため、openPaths/toggleが二重実行される(同じファイルの二重オープン、隠しファイル表示の二重トグル等)可能性がある。参照: code review finding(PLAUSIBLE), BefoldApp/befold/App/CLIInstanceRouter.swift:50
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同一requestIDの通知が複数回受信されても、受信側でopenPaths等の処理が一度しか実行されないこと
- [x] #2 回帰テストを追加する(実際のDistributedNotificationCenterに依存しない形で再現可能なテスト)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化を検討: AppDelegate に Set<String> を直接持たせる案も検討したが、重複排除ロジック自体を CLIRequestDeduplicator という独立した値型に切り出すことで、実際の DistributedNotificationCenter/AppDelegate 全体を経由せずロジック単体をユニットテスト可能にした(AC#2 の『実際のDistributedNotificationCenterに依存しない形で再現可能なテスト』を満たす)。ACK は再送のたびに毎回送り返す(元々の送信元は自分のACKロストで再送している可能性があるため)が、openPaths の実行は requestID ごとに一度だけに制限した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIInstanceRouter.forward() の再送(同一requestID)による handleCLIOpenRequest の二重処理(openPaths二重実行)を修正。requestID の重複排除ロジックを CLIRequestDeduplicator という独立した値型として切り出し、AppDelegate.handleCLIOpenRequest で ACK は毎回返しつつ openPaths の実行は requestID ごとに一度だけに制限した。CLIRequestDeduplicatorTests.swift に3件の回帰テスト(実際のDistributedNotificationCenterに依存しない)を追加。swift test --skip Integration --skip FileWatcherTests で536件全てパス。
<!-- SECTION:FINAL_SUMMARY:END -->
