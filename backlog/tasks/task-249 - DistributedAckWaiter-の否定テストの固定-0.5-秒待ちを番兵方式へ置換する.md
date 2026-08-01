---
id: TASK-249
title: DistributedAckWaiter の否定テストの固定 0.5 秒待ちを番兵方式へ置換する
status: To Do
assignee: []
created_date: '2026-08-01 10:46'
labels: []
dependencies: []
priority: low
type: task
ordinal: 451000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DistributedAckWaiterIntegrationTests.swift:34, 46 の「観測しない」系 2 テストが waiter.wait(timeout: 0.5) で毎回フルに 0.5 秒待つ(否定検証なのでタイムアウトまで必ず待ち、確定 1.0 秒のコスト)。0.5 秒という窓には配送遅延をどこまでカバーするかの根拠もない。
同一通知の配送で両 observer が呼ばれることを利用し、対象と別に番兵 waiter(sentinel)を立てて配送完了を肯定的に確認してから、対象 waiter が未観測であることを wait(timeout: 0) で検証する方式にすると、ms 級かつ決定的になり、負荷時の取りこぼしと区別がつかない曖昧さも消える。cancel 系テストも同じ方式(cancel していない同一 requestID の番兵で配送確認 → cancel 済み側が false)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 否定テスト 2 本が番兵方式になり固定 0.5 秒待ちが消える
- [ ] #2 配送完了を肯定的に確認してから未観測を検証する構造になっている
- [ ] #3 swift test が全てグリーン
<!-- AC:END -->
