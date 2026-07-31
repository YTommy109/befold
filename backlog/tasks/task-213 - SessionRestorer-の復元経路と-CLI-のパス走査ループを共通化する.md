---
id: TASK-213
title: SessionRestorer の復元経路と CLI のパス走査ループを共通化する
status: To Do
assignee: []
created_date: '2026-07-31 02:58'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/SessionRestorer.swift
  - BefoldApp/befold-cli/BefoldCLICommand.swift
priority: low
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(2026-07-31)の小粒の共通化候補 2 件。(1) SessionRestorer の「保存パスを実在ファイルで絞ってから復元」が openRepository(SessionRestorer.swift:90-99)と restoreLastSession(同 130-147)で「filter(isExistingFile) → urlByPath 構築 → SessionLayout.filtered → restoreTabGroup」の同一シーケンスとして重複。差分は restoreLastSession のみ消えたファイルに noteClosed を打つ点で、onMissing クロージャとして外出しすれば実行タイミングも回数も変わらない。restoreLayout(_:urls:options:onMissing:) に抽出する。(2) BefoldCLICommand.execute の --check / --bookmark ループ(befold-cli/BefoldCLICommand.swift:66-79): 「paths 走査 → コマンド実行 → printResult → 失敗フラグ集約」が同順序で 2 回。runForEachPath に抽出し、全パス実行してから exit 1 という結果集約の一貫性を 1 箇所に固定する。TASK-206(タブグループスナップショット共通化)と SessionRestorer で触る範囲が重なるため、着手順に注意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SessionRestorer の 2 復元経路が共通ヘルパーを使い、noteClosed の実行タイミング・回数を含め既存挙動が変わらない
- [ ] #2 CLI の check/bookmark ループが共通ヘルパーに統合され、終了コードの集約挙動が変わらない
- [ ] #3 既存テストが通る
<!-- AC:END -->
