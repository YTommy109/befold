---
id: TASK-244
title: GitCommandRunnerTests の直列化を資源残留系のみに限定し逐次 spawn を並行化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:45'
updated_date: '2026-08-01 15:00'
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
- [x] #1 .serialized が資源残留系スイートのみに限定される
- [x] #2 20 回の逐次 spawn が並行化または縮減される
- [x] #3 基準線ノイズ耐性が維持される根拠がテストコメントで説明される
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitCommandRunnerTests.swift を2スイートに分割する: 既存の struct 名を維持しつつ .serialized を外し(純関数3+自己完結の実git4+killsGrandchild計8テストを並行実行対象に)、readsOutputWhileGlobalQueueIsSaturated(:131)/repeatedTimeoutsDoNotAccumulateResources(:187)/releasesResourcesWhenWriteEndSurvivesTermination(:224)の3テストを新設 struct GitCommandRunnerResourceLeakTests(.serialized)へ移す。readsOutputWhileGlobalQueueIsSaturated はそれ自体は基準線を読まないが、プロセス全体のDispatchQueue.globalを飽和させ他2テストのreaderThreadCount計測にノイズを乗せるため同じ直列スイートに残す。
2. 共有ヘルパー(makeRunner/hangingBudget/runInBackground/hangingAliasArguments/makeHangingRepo/killSleepers/processExists/openPipeCount/readerThreadCount/threadName/rawGit/runTool/makeRepoWithFsmonitor/leakPollingBudget)は両スイートから使うため、struct外のfile-privateヘルパー関数 or 共通の enum namespace へ引き上げるか、両スイートに必要な分だけ複製せず1箇所に集約する。使用箇所を確認してから決める。
3. survivesTimeoutBeforeReadStarts の20回逐次spawnをThread+LockedBoxで並行化する(既存runInBackgroundと同じパターン)。テスト意図(timedOutCount>=1)は変えない。
4. 分割の妥当性(基準線ノイズ耐性が変わらないこと)をテストコメントに追記する。
5. swiftformat → swift build(警告なし) → swift test 全体グリーンを確認し、GitCommandRunnerTests関連の実行時間before/afterを記録。
6. セルフレビュー後コミット。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
スイートを GitCommandRunnerTests(並列) / GitCommandRunnerResourceLeakTests(.serialized, 3テスト) に分割。共有ヘルパーはファイルスコープのprivate関数へ集約し重複を回避。survivesTimeoutBeforeReadStartsの20回spawnをThread+LockedBoxで並行化。フィルタ実行: before 13.4s → after 9.66s(10 tests)。全体: 1009 tests / 10.9s でグリーン。

レビューでの実測により、起票時の前提(直列チェーンが実行時間の主因、通常+TSan の 2 実行で 6〜10 秒短縮の見込み)が誤りであったことが判明した。
実測: 全体のクリティカルパスは GitCommandRunnerResourceLeakTests(13.03s、2 位の ViewerStoreIntegrationTests 10.76s に 2.3 秒差の単独律速)。その支配項は releasesResourcesWhenWriteEndSurvivesTermination の 7.14s で、これは GitCommandRunner の terminationGrace = 5 秒 + hangingBudget 2 秒という固有の待ちに由来し、直列化とは無関係。
このため本タスクの正味の実行時間短縮は実質ゼロ(before 13.4s / after 13.1〜13.6s)。テスト側スコープで削れる余地はほぼなく(検証を捨てて 2 秒級テストを消しても床は 10.76s)、唯一の有効なレバーは terminationGrace の注入化(プロダクトコード変更のためスコープ外。TASK-255 として起票)。
本タスクの成果は実行時間ではなく安全性の是正: 当初の分割では並列側に残したテストが計測対象の資源(pipe / read スレッド)を生成しており、基準線が水増しされてリーク退行を静かに見逃す状態になっていた(レビューで実行ログの重なりを観測)。GitCommandRunner を実行するテストは一律で直列側に置く基準へ改め、根拠をコメントに残した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitCommandRunnerTests の .serialized を資源残留系スイート(GitCommandRunnerResourceLeakTests)へ限定し、逐次 20 回の git spawn を並行化した。
当初は純関数テスト以外も並列側へ出したが、レビューで「並列側に残したテストが計測対象の資源(pipe / read スレッド)を生成しており、資源残留テストが開始時点で 1 回だけ読む基準線を水増しして、リーク退行を静かに見逃す(落ちるのではなく通ってしまう)」と判明。GitCommandRunner を実行するテストは一律で直列側に置く基準へ改め、その根拠を両スイートの型コメントに残した。
実行時間: 起票時の見積もり(6〜10 秒短縮)は前提が誤りで、正味の短縮は実質ゼロ(before 13.4s / after 13.1〜13.6s)。実測により全体の律速は GitCommandRunnerResourceLeakTests(13.07s)で、その支配項は terminationGrace 5 秒 + hangingBudget 2 秒に由来する 7.14s の 1 テストと判明した(直列化とは無関係)。唯一の有効な短縮レバーは terminationGrace の注入化で、TASK-255 として起票済み。
本タスクの成果は実行時間ではなく、.serialized の適用範囲が「たまたま同じファイルにあるから」から「基準線を汚しうるから」という説明可能な基準に変わったこと。
検証: swift test 1006 tests グリーン、TSan フィルタ実行もグリーン。レビュー承認済み(Critical 1 件 + Minor 1 件を解消)。
<!-- SECTION:FINAL_SUMMARY:END -->
