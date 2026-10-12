---
id: TASK-702
title: CLI から新規窓で開けるようにする (--new-window)
status: To Do
assignee: []
created_date: '2026-10-12 13:08'
labels:
  - cli
dependencies: []
priority: low
ordinal: 891000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI 経路は OpenDisposition が既定の .currentTab に固定（DocumentOpener）で、窓の再利用は ViewerWindowOpenPolicy 任せ。再利用せず新規窓で開きたい場合に CLI から選べない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `--new-window` で OpenDisposition.newWindow により開ける
- [ ] #2 パス必須の制約と --check/--bookmark 併用不可が既存オプションと揃っている
- [ ] #3 ワイヤ形式に追加する場合、旧 CLI/旧本体との組み合わせでの挙動をテストで担保する
- [ ] #4 README・docs/dev/cli-launch.md を更新する
<!-- AC:END -->
