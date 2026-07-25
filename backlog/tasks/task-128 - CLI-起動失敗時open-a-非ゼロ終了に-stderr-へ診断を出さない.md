---
id: TASK-128
title: CLI 起動失敗時(open -a 非ゼロ終了)に stderr へ診断を出さない
status: To Do
assignee: []
created_date: '2026-07-24 22:22'
labels:
  - cli
  - bug
dependencies: []
priority: medium
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。befold-cli/CLIAppLauncher.swift:79 で /usr/bin/open -a が非ゼロ終了したとき、run() は raw status をそのまま返し stderr に何も書かない(直下の throw 経路は writeError でメッセージを書くのと非対称)。
befold.app が削除・破損している状態で `befold diagram.mmd` を実行すると、非ゼロ exit だが出力ゼロで、パス間違いなのかアプリ欠落なのか転送失敗なのか判別できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 open -a 非ゼロ終了時に原因が分かるメッセージを stderr へ出力する
- [ ] #2 この経路のテストがある
<!-- AC:END -->
