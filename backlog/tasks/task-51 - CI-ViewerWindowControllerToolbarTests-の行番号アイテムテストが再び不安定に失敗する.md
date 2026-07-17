---
id: TASK-51
title: 'CI: ViewerWindowControllerToolbarTests の行番号アイテムテストが再び不安定に失敗する'
status: To Do
assignee: []
created_date: '2026-07-17 09:12'
updated_date: '2026-07-17 09:12'
labels:
  - ci
  - bug
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/29568618799'
priority: high
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #239 の CI run https://github.com/YTommy109/befold/actions/runs/29568618799 (build-and-test / テストを実行する) で ViewerWindowControllerToolbarTests.swift:64 の Test "行番号アイテムはコード表示中のみ有効" が再び失敗した(codeButton.isEnabled → false) == true)。task-34 でポーリングで取得したボタンを使い回す修正を行い8回連続成功を確認していたが、今回また同じテストが失敗している。task-34 の修正が不十分だったか、別の競合要因が残っている可能性がある。task-35 の作業中に偶然検出したもので、task-35 の変更(ci.ymlのアクションバージョン更新)自体とは無関係と判断している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GHA run 29568618799 の失敗ログと task-34 の修正差分を照合し、再発原因を特定する
- [ ] #2 task-34 の修正で解消しきれていない競合要因を特定する
- [ ] #3 原因に応じて実装またはテストを修正し、CI で複数回にわたり安定して通ることを確認する
<!-- AC:END -->
