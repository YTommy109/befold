---
id: TASK-346
title: ThreadSanitizer CI で「同じファイルを 2 窓で開いても git diff は 1 回に合流する」が失敗する
status: To Do
assignee: []
created_date: '2026-08-07 00:53'
labels:
  - test
  - flaky
  - ci
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/31080059382'
priority: high
type: bug
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
main の CI（run 31080059382, 2026-08-06 push）で ViewerWindowManagerDiffTests「同じファイルを 2 窓で開いても git diff は 1 回に合流する」が失敗した。1171 テスト中この 1 件のみで、ThreadSanitizer ジョブでのみ発生している。

失敗内容: `ViewerWindowManagerDiffTests.swift:152` で `Expectation failed: (reader.callCount → 3) == (before + 1 → 2)`。当該テストは TSan 下で 125.074 秒かかっている（ローカルの単独実行は 1.348 秒で通過、2026-08-07 実測）。

見立て（コード参照ベース、未再現）:
- `GitDiffLoader.swift:60-67` の畳み込みは、要求チケットが走行中の取得より古い場合は相乗りせず、走行中の完了を待ってから取り直す。つまり「取得が 1 回完了した」時点でも後追いの再取得が残っていることがある。
- テストの静止待ちは `controllers.allSatisfy { $0.store.diffText == "DIFF" }`（同ファイル:136-138）で、最初の取得完了で成立してしまい、後追いの再取得が残っているかを区別しない。その直後に `before = reader.callCount`（:139）を採取している。
- セットアップ（openViewer → switchFile → presentDocument → gitStatusDidApply）が複数の契機を出すため古いチケットの再取得が 1 本残り、それが before 採取後に着弾して +1、続く 2 窓の refreshDiff() が合流して +1 で計 3。観測値 3 と整合する。
- テストは `delay: 0.2` と `Task.sleep(600ms)`（:114, :151）という壁時計の時間窓に依存しており、TSan の減速（約 90 倍）で窓が崩れる。

同型の再発である点に注意（CLAUDE.md「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」）。TASK-327 は、壁時計ポーリングと @MainActor 飽和に依存したテストが全体実行で落ちる問題を CLI 側 2 件で個別修正した。本件は 3 件目にあたるため、待機の秒数を伸ばす対症療法ではなく、静止判定を時間ではなく内部状態（GitDiffLoader の in-flight 件数など）で行う形へ移すことを検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 当該テストが ThreadSanitizer 付きの CI で 10 回連続して失敗しない
- [ ] #2 静止判定が壁時計の待ち時間ではなく、取得が走行中でないことを表す内部状態に基づいている
- [ ] #3 修正を戻すと当該テストが落ちることを確認している（合流ロジックの回帰検知能力を失っていない）
<!-- AC:END -->
