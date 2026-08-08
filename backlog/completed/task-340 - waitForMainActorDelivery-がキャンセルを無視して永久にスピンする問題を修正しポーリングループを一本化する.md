---
id: TASK-340
title: waitForMainActorDelivery がキャンセルを無視して永久にスピンする問題を修正しポーリングループを一本化する
status: Done
assignee: []
created_date: '2026-08-06 05:35'
updated_date: '2026-08-06 06:31'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。b0b6942a で追加した BefoldTestSupport/Waiting.swift:127-139 の waitForMainActorDelivery が対象。

問題 1（キャンセル無視）: 唯一の suspension point が `try? await Task.sleep(...)` で CancellationError を握りつぶし、ループ条件もキャンセルを見ない（Task.isCancelled / checkCancellation はファイル内に存在しない）。@Test の .timeLimit がテストタスクをキャンセルした後は sleep が即時 throw し続け、Date() 比較のホットスピンになり、外側ループが action()（一時ファイルの再書き込み）を 0.5 秒ごとに永久に実行する。本物の FileWatcher リグレッションで条件が恒久 false になると、swift test 全体が CPU 100% でハングし、失敗テスト名も出ないまま CI のジョブタイムアウトまで走る。

問題 2（重複、同根）: 同関数は waitUntilWithRetry のリトライ/ポーリングループをほぼ逐語コピーしており（外側の wall-clock deadline を外しただけ）、同ファイル内 4 つ目のポーリングループ。キャンセル対応の修正を 1 箇所で済ませるため、既存ヘルパー経由（deadline = .distantFuture 等）か内側ループの抽出で実装を一本化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テストタスクのキャンセル後、waitForMainActorDelivery が速やかに return しホットスピンしない
- [x] #2 ポーリングループの実装が一本化され、waitForMainActorDelivery が既存ヘルパーまたは共通の内側ループを使う
- [x] #3 キャンセルで抜けることを検証するテストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Waiting.swift の 4 つのポーリングループを pollUntil / pollWithRetry の 2 つの共通実装（isolation: isolated (any Actor)? = #isolation で MainActor 版とも共有）へ一本化し、両者がキャンセルを見て抜けるようにした。キャンセルでの離脱は Issue.record しない。WaitingTests の 2 件は修正を戻すと落ちる（実測: 5 秒待っても待機が戻らず、キャンセル後も action が 501→522 と増える）。swift test 1171 件グリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
