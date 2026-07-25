---
id: TASK-130
title: confirmWatcherArmed の静穏化カットオフが遅い CI で flaky 化しうる
status: To Do
assignee: []
created_date: '2026-07-24 22:23'
labels:
  - test
  - ci
dependencies: []
priority: medium
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で PLAUSIBLE 判定。befoldTests/TestSupport.swift:40 で静穏化待ちが無制限ループから quiescePeriod * 20(デフォルト 0.3s で 6 秒)の固定カットオフに変更され、超過時に Issue.record でテストを fail させる。
thread-sanitizer ジョブのような遅い CI(BEFOLD_TEST_TIMEOUT_SECONDS=120 に延長される環境)では、arm プローブ書き込み+デバウンスされたイベントが quiescePeriod 未満の間隔で 6 秒以上到着し続けることがあり、旧実装なら待って成功していたケースが赤くなる。カットオフが BEFOLD_TEST_TIMEOUT_SECONDS と連動しないのが根本原因。TASK-116.6(thread-sanitizer ジョブの慢性的失敗解消)と関連。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 カットオフが BEFOLD_TEST_TIMEOUT_SECONDS(またはテスト環境のスケール係数)と連動する
- [ ] #2 thread-sanitizer 相当の遅延環境でも confirmWatcherArmed が誤 fail しない
<!-- AC:END -->
