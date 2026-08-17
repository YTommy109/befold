---
id: TASK-509
title: TSan ジョブで残っていた壁時計待機を loadTask の await へ移す
status: To Do
assignee: []
created_date: '2026-08-17 04:34'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 739000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブ（push / schedule でのみ実行）が、コンテンツロードの着地を壁時計ポーリングで待つ 4 箇所で断続的に落ちている。

## 事実

- 失敗メッセージはすべて `waitUntilOnMainActor が 120.0 seconds 以内に条件を満たさなかった`。TSan の data race 報告は 0 件（run 31993974965 のログ全文を grep 済み）。
- 同じ 8 テストが 2026-08-15 の main 実行（run 31885189333）でも同じ形で落ちている。thread-sanitizer は push / schedule のみで走るため（.github/workflows/ci.yml:214）PR では検出できない。
- 失敗箇所は BefoldApp/befoldTests/ViewerWindowControllerDiffTests.swift:206 / 239 / 286 と ViewerWindowControllerDiffPendingTests.swift:120（preparePresentedMarkdown 内）。いずれも差分取得ではなく初回コンテンツロードの着地を待っている。ViewerWindowControllerDiffPendingTests.swift:58 の Expectation failed は、その待機がタイムアウトして前提が崩れた下流の症状。
- git のサブプロセスは起動していない（ViewerWindowControllerFixture が InMemoryFileReader / MockFileWatcher / テストダブルの gitFileIndex を注入）。ロジック上のハングは見つかっていない。
- waitUntilOnMainActor の締切は壁時計（BefoldTestSupport/Waiting.swift:124）。一方 swift test は 1603 テストをほぼ同時に開始しており（全テストが 04:21:04 に start、成功したテストも 185〜230 秒かかったと報告される）、120 秒の予算は操作の所要ではなくスイート全体の混雑時間を測っている。

## 同型の 2 回目である

backlog/completed/task-437 が同じ失敗メッセージ・同じジョブに対して「壁時計予算では上限を決められない」と結論し（予算を 10 → 60 → 120 と伸ばして 120 でも落ちた）、差分取得側だけを await task へ移行した。その AC#3 で今回の 3 箇所を「コンテンツロード確定を待つ別経路のため対象外」として明示的に残していた。CLAUDE.md の「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」に該当するため、予算をさらに伸ばす対処は採らない。

## 方針

待機そのものを消す。修正パターンは既にコードベースにあり、befoldTests/ViewerWindowControllerToolbarTests.swift:133-138 に「壁時計予算のポーリング(waitUntilOnMainActor)ではなく loadTask を await する」というコメント付きの実例がある（await controller.store.loadTask?.value）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWindowControllerDiffTests.swift の 3 箇所と ViewerWindowControllerDiffPendingTests.swift の 1 箇所から、コンテンツロード着地を待つ waitUntilOnMainActor が消え、store.loadTask の await に置き換わっている
- [ ] #2 befoldTests 全体を grep し、コンテンツロード着地を壁時計で待つ waitUntilOnMainActor が他に残っていないことを確認し、残す場合は理由を Implementation Notes に書く
- [ ] #3 swift test がローカルで通る（失敗ゼロ、テスト名まで確認する）
- [ ] #4 main へマージ後の thread-sanitizer ジョブが通ることを確認する（PR では走らないため、マージ後の run を必ず見る）
<!-- AC:END -->
