---
id: TASK-361.2
title: サイドバーの git ステータスを複数ディレクトリ対応にする
status: To Do
assignee: []
created_date: '2026-08-10 01:57'
labels: []
dependencies:
  - TASK-361.1
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 656000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの git ステータスを、単一ディレクトリぶんから**複数ディレクトリぶん**へ拡張する。TASK-361 の動機（コードレビュー中に複数フォルダへ散らばった変更ファイルを行き来する）に直接効く部分であり、行モデルを一本化しても残る本質的な設計変更。

## 現状（実測 2026-08-10、HEAD a3202d4）

- App/SidebarGitStatus.swift:16 が `let directoryKey` を 1 つだけ持つ（1 ディレクトリぶんのスナップショット）
- Viewer/FileListFilter.swift:47 gitChangeFilter(for:) が `gitStatus.directoryKey == directory.normalizedPathKey` で不一致なら nil を返す
- Viewer/FileListModel.swift:193 / :214 も entriesDirectory.normalizedPathKey と突き合わせる

複数階層を同時表示すると、1 つの directoryKey では表示中の行に対応付けできない。

## 方針

- SidebarGitStatus を「directoryKey → ステータス」の対応（辞書等）へ拡張するか、行の pathKey で直接引ける形へ変える。どちらにするかは /review-design で決める
- 「変更されたファイルのみ表示」（App/SidebarDisplayPreference.swift:23 showChangedFilesOnly）が、表示中のすべての階層に対して効くようにする
- バッジ表示（GitStatusBadge 系）も同様に、行ごとの pathKey で解決する

## 制約

- FeatureGate 配下（サイドバー git ステータスは TASK-187 でまだ stable 未昇格）に触れるため、コミット件名に (gate) スコープを付けるか判断すること。判断基準は FeatureGate.swift の Bool を経由してのみ有効化されるか
- 着手前に /review-design を 1 回回すこと
- 既存テスト SidebarGitStatusTests(5) / SidebarNavigatorGitStatusTests(9) / SidebarChangedFilesOnlyIntegrationTests(4) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git ステータスが複数ディレクトリぶん保持でき、表示中のどの階層の行でもバッジが正しく解決される
- [ ] #2 「変更されたファイルのみ表示」が、表示中のすべての階層に対して効く
- [ ] #3 単一ディレクトリ（ドリルダウン）時の既存の振る舞いと既存テストが壊れていない
- [ ] #4 対応付けが単一 directoryKey へ戻ったら落ちるテストがある
<!-- AC:END -->
