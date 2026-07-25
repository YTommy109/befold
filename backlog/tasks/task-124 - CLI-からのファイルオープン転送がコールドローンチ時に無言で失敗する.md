---
id: TASK-124
title: CLI からのファイルオープン転送がコールドローンチ時に無言で失敗する
status: To Do
assignee: []
created_date: '2026-07-24 22:21'
labels:
  - cli
  - bug
dependencies: []
priority: high
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。CLIInstanceRouter.forward()(CLIInstanceRouter.swift:73)は「ACK なしだが宛先プロセスが生存」を成功扱いにする。コールドローンチ時、AppDelegate が DistributedNotificationCenter の observer を登録する前に NSRunningApplication でアプリが検出され、リトライ総枠も maxForwardAttempts(3) × ackTimeout(0.5s) = 1.5s しかない(コードコメント自体がこの制約を認めている)。
遅いコールドスタート(アップデート直後の初回起動・遅いディスク)では 3 回の通知投稿がすべて observer 登録前に発火し、CLI は exit 0 するがファイルは開かず、エラーも表示されない。
関連: CLIInstanceRouter.swift:67 では post が waitForAck の observer 登録より先に実行されるため、post 直後〜登録前の窓とリトライ間の removeObserver の隙間で ACK を取りこぼす問題も同根。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コールドローンチ時に `befold file.md` で確実にファイルが開く(observer 登録前の転送が失われない)
- [ ] #2 転送が最終的に失敗した場合、CLI は非ゼロ exit とエラーメッセージを出す
- [ ] #3 ACK 登録と post の順序に関する競合のテストがある
<!-- AC:END -->
