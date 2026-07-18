---
id: TASK-51
title: 'CI: ViewerWindowControllerToolbarTests の行番号アイテムテストが再び不安定に失敗する'
status: Done
assignee: []
created_date: '2026-07-17 09:12'
updated_date: '2026-07-18 07:38'
labels:
  - ci
  - bug
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/29568618799'
priority: high
ordinal: 4687.5
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #239 の CI run https://github.com/YTommy109/befold/actions/runs/29568618799 (build-and-test / テストを実行する) で ViewerWindowControllerToolbarTests.swift:64 の Test "行番号アイテムはコード表示中のみ有効" が再び失敗した(codeButton.isEnabled → false) == true)。task-34 でポーリングで取得したボタンを使い回す修正を行い8回連続成功を確認していたが、今回また同じテストが失敗している。task-34 の修正が不十分だったか、別の競合要因が残っている可能性がある。task-35 の作業中に偶然検出したもので、task-35 の変更(ci.ymlのアクションバージョン更新)自体とは無関係と判断している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GHA run 29568618799 の失敗ログと task-34 の修正差分を照合し、再発原因を特定する
- [x] #2 task-34 の修正で解消しきれていない競合要因を特定する
- [x] #3 原因に応じて実装またはテストを修正し、CI で複数回にわたり安定して通ることを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GHA run 29568618799 の失敗ログ(gh run view --log-failed)を取得し、失敗テストと所要時間を確認する
2. task-34 の修正差分(ポーリングで取得したボタンをそのまま使い回す)が該当箇所に適用済みか現在のテストコードを確認する
3. task-34 と同一 CI run(29568618799)で task-50(detectsFileDeletion)も同時に失敗しており、そちらは10秒のデフォルトポーリングタイムアウト超過が原因と判明し 64eb757 で build-and-test ジョブに BEFOLD_TEST_TIMEOUT_SECONDS: 30 を追加済みであることを確認する
4. 過去の失敗ログ(29568618799: 18.809秒, 29568058652: 16.371秒, 29569555911: 13.541秒, task-34時点の29548044711: 13.989秒)がいずれも当時のデフォルト10秒を超過しており、同一の原因(CI輻輳によるポーリングタイムアウト超過)であると推定する
5. ローカルで BEFOLD_TEST_TIMEOUT_SECONDS を極端に短く設定して意図的にタイムアウトさせ、CI と同一のエラーメッセージ(codeButton.isEnabled → false)が再現することを確認し、二重フェッチ競合ではなくタイムアウト超過が原因であるという仮説を検証する
6. 単純化検討: 新たなリトライ機構やポーリング設計変更は追加せず、既に task-50 対応で build-and-test ジョブ全体に適用済みの BEFOLD_TEST_TIMEOUT_SECONDS: 30 がこのテストにも及ぶため、追加のコード変更は不要と判断する
7. ローカルで通常のタイムアウト設定のまま複数回実行し安定して成功することを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査結果: task-51が参照する run 29568618799 は、同じ run で task-50(detectsFileDeletion)も失敗していた。task-50の調査で、その原因はCIランナーの一時的な低速化によりwaitUntilのデフォルト10秒ポーリング予算を超過したことと判明し、64eb757で build-and-test ジョブに BEFOLD_TEST_TIMEOUT_SECONDS: 30 を追加済み(既にこのブランチに取り込まれている)。

lineNumbersItemEnabledOnlyForCodeContent の過去の失敗ログを横断的に確認した結果、失敗時の所要時間は 29568618799: 18.809秒、29568058652: 16.371秒、29569555911: 13.541秒、task-34調査時の29548044711: 13.989秒 で、いずれも「通常1秒未満」に対し異常に長く、かつ当時のデフォルト10秒(task-34/このタスクの各runはBEFOLD_TEST_TIMEOUT_SECONDS未設定のbuild-and-testジョブ)を超過している。これはtask-50と同一のCI輻輳によるポーリングタイムアウト超過パターンであり、二重フェッチによる状態競合ではないと判断した。

仮説検証: ローカルで BEFOLD_TEST_TIMEOUT_SECONDS=0.001 を設定して意図的にポーリングをタイムアウトさせたところ、CI と全く同じエラーメッセージ「Expectation failed: (codeButton.isEnabled → false) == true」がViewerWindowControllerToolbarTests.swift:64で再現した。これにより、taskの実際の失敗経路は「ポーリングが条件成立前にタイムアウトし、その時点の(まだ無効な)ボタンを掴んだまま#expectに到達する」ことだと確認できた。

task-34の修正(ポーリングで取得したボタンをそのまま使い回す)自体は妥当な変更だが、当時のtask-34の原因特定(『二段階の非同期フェッチが競合ウィンドウを生む』)は誤りで、実際はタイムアウト超過が原因だったと考えられる(task-34時点の失敗も13.989秒で当時のデフォルト10秒を超過していた)。そのため『task-34の修正で解消しきれていない競合要因』というAC#2の前提(競合要因が別に残っている)は誤りで、真因はCI輻輳によるタイムアウト予算不足であり、task-50対応(64eb757、build-and-testジョブへのBEFOLD_TEST_TIMEOUT_SECONDS:30追加)で既に解消済みと判断する。

単純化検討: 新たなリトライ機構・ポーリング設計変更・タイムアウト個別延長は追加せず、既存の仕組み(BEFOLD_TEST_TIMEOUT_SECONDS)がbuild-and-testジョブ全体に及んでいることを確認するだけで十分と判断し、コード変更は行わなかった。

検証: swift test(366テスト)全件成功。ViewerWindowControllerToolbarTestsを通常設定で複数回連続実行し全て成功(0.5秒台で安定)。

CI確認(AC#3): PR #242(chasm-mirage)を push し、build-and-test を3回連続実行して全て成功を確認した。
- run 29635808259 (1回目): 行番号アイテムはコード表示中のみ有効 が 18.665秒で成功
- 同run 再実行(2回目): 18.530秒で成功
- 同run 再実行(3回目): 8.887秒で成功
いずれも旧デフォルト10秒は超過する所要時間だが、現行の BEFOLD_TEST_TIMEOUT_SECONDS: 30(task-50対応, 64eb757)により安定して成功しており、真因がタイムアウト予算不足だったという判断を裏付ける。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
task-51が参照するCI run 29568618799のViewerWindowControllerToolbarTests再発を調査した結果、同一runで失敗していたtask-50(detectsFileDeletion)と同じ根本原因(CIランナーの一時的な低速化によるwaitUntilOnMainActorのデフォルト10秒ポーリング予算超過)であると判明した。ローカルでBEFOLD_TEST_TIMEOUT_SECONDS=0.001を設定して意図的にタイムアウトさせ、CIと同一のエラーメッセージ(codeButton.isEnabled → false)が再現することで裏付けた。task-34の『二段階非同期フェッチの競合』という原因特定は誤りで、実際は当時からタイムアウト超過が真因だった(task-34調査時の失敗も13.989秒でデフォルト10秒を超過)。task-50対応(64eb757、build-and-testジョブへのBEFOLD_TEST_TIMEOUT_SECONDS:30追加)がこのブランチに既に取り込まれておりこのテストにも適用されるため、単純化方針に沿って追加のコード変更は行わなかった。PR #242を push し、build-and-testを3回連続実行して全て成功(18.665秒/18.530秒/8.887秒)を確認し、AC#3を満たした。
<!-- SECTION:FINAL_SUMMARY:END -->
