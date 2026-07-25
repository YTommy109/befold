---
id: TASK-148
title: GitCommandRunner を絶対パス・最小環境・先回り無害化オプションで堅牢化する
status: To Do
assignee: []
created_date: '2026-07-25 11:30'
labels:
  - path-reference
  - security
dependencies: []
priority: medium
type: task
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー指摘（低 L-3 / L-4）。(1) GitCommandRunner.swift L38 が /usr/bin/env git + 無加工の継承環境で実行しており、PATH 先頭の偽 git や GIT_CONFIG_COUNT/GIT_CONFIG_KEY_*・GIT_DIR 等の環境変数が -c 無害化を上書きしうる。(2) 現行の hardeningOptions は rev-parse/ls-files の 2 コマンドに対しては十分だが、将来コマンド追加時に core.pager・diff.external・textconv・credential.helper 等が新たな実行経路になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 executableURL を /usr/bin/git に固定し、process.environment を最小集合（PATH 固定、GIT_* 除去）に差し替える
- [ ] #2 hardening に `-c core.pager=cat`（または --no-pager）、GIT_PAGER=cat、GIT_TERMINAL_PROMPT=0 を追加する
- [ ] #3 `core.fsmonitor=` の空文字指定を false に変えて意図を明確化する
- [ ] #4 GitCommandRunnerTests で環境最小化・無害化オプションの内容を固定する
<!-- AC:END -->
