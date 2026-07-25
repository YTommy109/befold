---
id: TASK-134
title: CLIInstanceRouter のワイヤプロトコルを Codable ペイロード化し送受の責務を分離する
status: To Do
assignee: []
created_date: '2026-07-24 22:40'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: medium
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward(送信)が CLIOpenOptions の各フィールドを showHiddenFiles/showLineNumbers/sourceMode/showSidebar/sortOrder の文字列キーへ手写しで詰め、decode(userInfo:)が同じ文字列キーを手で読み戻す。CLIOpenOptions は Codable なのにワイヤ表現で活用されず、フィールド追加時に forward/decode/AppDelegate/ViewerWindowManager/SessionRestorer を同時修正する shotgun surgery になる(過去 TASK-82/87 の転送取りこぼしの温床)。加えて CLIInstanceRouter enum が インスタンス探索・送信リトライ+busy-wait・受信/ACK ワイヤプロトコル の異質な 3 責務を同居させ、CLI 側と GUI 側が半分ずつしか使わないのに双方が enum 全体(AppKit/DistributedNotificationCenter 依存)をリンクする。dagayn SAP 指摘(BefoldCLI distance=1.0)の中核。ACK タイミングの TASK-85/88/89 とは別関心で、本タスクは責務分割・依存方向とペイロード表現を対象とする。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLIOpenOptions が JSONEncoder/Decoder で単一キーのペイロードとして送受され、文字列キーの手写しミラーが解消している
- [ ] #2 CLIOpenOptions へのフィールド追加が構造体定義のみの変更で完結する(送受のドリフト面がない)
- [ ] #3 ワイヤプロトコル(通知名+encode/decode/sendAck)が受信側と共有する薄い型に切り出され、送信側の探索/リトライ/busy-wait が送信専用の配置へ寄っている
- [ ] #4 GUI 側が受信プロトコルのみをリンクし、送信専用の探索・リトライ・AppKit 起動依存を負わない
- [ ] #5 CLI→GUI のファイルオープン転送が全オプション込みで回帰なく動作する
<!-- AC:END -->
