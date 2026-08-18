---
id: TASK-516
title: TSan ジョブで BlockingGate が開かれないまま 120 秒上限に達し «unknown» issue で run が落ちる
status: To Do
assignee: []
created_date: '2026-08-18 11:25'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 756000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブが、全スイート pass でありながら 2 件の «unknown» issue で exit 1 になる。

## 事実（実測）

- run [32025054306](https://github.com/YTommy109/befold/actions/runs/32025054306)（main / commit c6b76b66）の thread-sanitizer ジョブ。
  `✘ Test «unknown» recorded an issue at GitStatusStoreTests.swift:73:38: Issue recorded` が 2 件。
  `✘ Test run with 1607 tests in 255 suites failed after 258.892 seconds with 2 issues.`
- 他ジョブ（build-and-test / js-test / type-group-size）はすべて成功しており、TSan ジョブ限定。
- `GitStatusStoreTests.swift:73` は `FakeReader.status` 内の `block.wait("FakeReader.status")`。
  `BlockingGate.wait` は `BEFOLD_TEST_TIMEOUT_SECONDS`（TSan ジョブでは 120）で上限に達すると
  `Issue.record` する（BlockingWait.swift:34-40）。つまりゲートが **open() されないまま 120 秒経過**した。
- このゲートを使う唯一のテストは `foldsConcurrentRequestsForSameRoot`（GitStatusStoreTests.swift:210-239）。
  `release.open()` は `await secondRootResolved.wait()` の後にしか実行されない（:233-234）。
- `BlockingGate` は TASK-427 で「テスト終了後の余分な呼び出しが永久に詰まらないよう」開閉フラグ方式に
  したもので、doc コメント（BlockingWait.swift:44-54）が本件とまったく同じ現れ方
  （全 pass でも «unknown» 1 件で run が落ちる / PR #468 の run 31386949217）を記録している。
  今回は同じ症状が別のゲートで再発している。

## 構造上の問題（推測を含む）

`release.wait()` は **Swift concurrency の協調スレッドを同期的に塞ぐ**。塞いだまま、
解放に必要な `secondRootResolved.open()` を別タスクの前進に依存しているため、
TSan（5〜15 倍のスローダウン）と 1600 件超の並列実行で協調スレッドが枯渇すると
前進保証が壊れ、`release.open()` に到達しない。

**未確認**: この推測は実測していない。`swift test --sanitize=thread --filter GitStatusStoreTests` を
反復しても単独では再現しない見込みで（並列度が足りない）、全件実行の反復か、
協調スレッド数を絞った実行（`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 等）で確かめる必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TSan 相当（swift test --sanitize=thread）の全件実行を反復し、«unknown» issue が出ないことを実測する
- [ ] #2 foldsConcurrentRequestsForSameRoot が協調スレッドを同期的に塞がない形になっている、または塞いでも前進が保証される根拠が示されている
- [ ] #3 同じ形（同期ブロック + 別タスクの前進に依存した解放）が他のテストに無いことを確認し、あれば併せて直すか別タスクへ申し送っている
<!-- AC:END -->
