---
id: TASK-312
title: build-and-test で資源残留テストが待機予算 60 秒を使い切って落ちることがある
status: To Do
assignee: []
created_date: '2026-08-05 03:15'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実測: CI run 30962672970 の build-and-test で GitCommandRunnerResourceLeakTests の "殺し切れない孫が標準出力を握っていてもスレッドと fd は返る" が `waitUntil が 60.0 seconds 以内に条件を満たさなかった`(GitCommandRunnerTests.swift:475) で失敗した。TSan 側の恒常失敗(.timeLimit の直書き)とは別で、こちらは打ち切りではなく**ポーリング予算そのものの枯渇**。

背景として、このスイートは 1105 テスト並列の輻輳を強く受ける。同一 run では無関係なテストが揃って 13.0〜13.5 秒・24.5 秒といった同値の所要時間を報告しており、テストの所要時間がスイート全体の wall time に張り付いている(別調査で、@MainActor テストが `GitTestRepo.run` の `Process.waitUntilExit()` で main actor をブロックしながら git を起動するため、main actor が長大な直列キューになることを実測済み)。したがって「fd/スレッドが返るまで」の観測が 60 秒に収まらない事象は輻輳次第で再発しうる。

判断が必要なのは、これを (a) 予算(`BEFOLD_TEST_TIMEOUT_SECONDS`, ci.yml の build-and-test 既定 60)の引き上げで吸収するのか、(b) 資源解放が本当に遅い実装上の問題として扱うのか。単発観測のため、まず再現頻度の確認から。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 当該テストの失敗が輻輳由来か実装由来かを、再実行またはログの実測で切り分けている
- [ ] #2 輻輳由来なら予算・直列化のいずれで吸収するかを決め、根拠を Notes に残している
- [ ] #3 実装由来なら fd/スレッド解放の遅延箇所を特定し、修正で失敗が再現しないことを確認している
<!-- AC:END -->
