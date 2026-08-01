---
id: TASK-244
title: GitCommandRunnerTests の直列化を資源残留系のみに限定し逐次 spawn を並行化する
status: To Do
assignee: []
created_date: '2026-08-01 10:45'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 446000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandRunnerTests.swift:19 の @Suite(.serialized) が全 9 テストを直列化しているが、直列が必要なのはプロセス全体の基準線(openPipeCount / readerThreadCount)を読む資源残留系 3 テスト(:131, :187, :224)のみ。純関数テスト(:28, :38, :48)や自己完結の実 git テスト(:61, :82, :101)まで hanging-git 系(hangingBudget 2 秒+ポーリング予算)の直列チェーンの後ろに並んでいる。
また survivesTimeoutBeforeReadStarts(:107-118)が git --version を 20 回逐次 spawn(1〜2 秒)。既存の runInBackground(:249)と同様に並行に投げて waitUntil で回収するか、回数を 8 程度に減らせる。
スイート 2 分割(並列のままの本体 + .serialized の GitCommandRunnerResourceLeakTests)+ spawn 並行化で、通常 + TSan の 2 実行合計 6〜10 秒規模の短縮見込み。.serialized はスイート内しか直列化しないため、他スイートとの並行ノイズは既に slack 側(:213-215)で吸収されており分割しても検証力は変わらない。
関連: TASK-226(GitCommandRunner async 化・GitCommandFileIndex actor 化)と実装が重なる可能性があるため、着手時に整合を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .serialized が資源残留系スイートのみに限定される
- [ ] #2 20 回の逐次 spawn が並行化または縮減される
- [ ] #3 基準線ノイズ耐性が維持される根拠がテストコメントで説明される
- [ ] #4 swift test が全てグリーン
<!-- AC:END -->
