---
id: TASK-119
title: CLI オプションでサイドバーの表示/非表示を指定できるようにする
status: To Do
assignee: []
created_date: '2026-07-24 04:38'
labels:
  - cli
  - feature
dependencies: []
priority: medium
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動時の CLI オプションでサイドバーのオン/オフを指定できるようにする。既存の表示オプション(--hidden-files / --sort / --line-numbers / --source など)と同様に、指定が無ければ保存済み設定・既定値を維持する。CLIOpenOptions / OpenCLIOptions / CLIInstanceRouter の転送・復元、および GUI 側の適用まで一貫して反映する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバー表示/非表示を指定する CLI オプションが --help に表示される
- [ ] #2 オプション指定に応じて起動したウィンドウのサイドバーが開いた/閉じた状態になる
- [ ] #3 オプション未指定時は既存の保存済みサイドバー状態・既定値を維持する
- [ ] #4 パス無し指定・既存インスタンスへの転送でも同様に反映される
<!-- AC:END -->
