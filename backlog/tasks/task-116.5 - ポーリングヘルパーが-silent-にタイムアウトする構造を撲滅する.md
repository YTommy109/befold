---
id: TASK-116.5
title: ポーリングヘルパーが silent にタイムアウトする構造を撲滅する
status: To Do
assignee: []
created_date: '2026-07-23 23:19'
labels:
  - test
  - ci
dependencies: []
parent_task_id: TASK-116
priority: high
ordinal: 30500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ブランチ以前から存在する構造的欠陥。テストが「10〜15 秒を丸ごと浪費した上でグリーンになる」ため、壊れた検証が壊れたまま通り続ける。

## 1. 全ポーリングヘルパーがタイムアウトを呼び出し側に伝えない

| ヘルパー | 定義 | 既定タイムアウト | 戻り値 |
|---|---|---|---|
| `waitUntil` | `BefoldApp/befoldTests/TestSupport.swift:91-100` | 10 秒 | Void |
| `waitUntilOnMainActor` | 同 :104-114 | 10 秒 | Void |
| `waitUntilWithRetry` | 同 :120-134 | 15 秒 | Void |
| `waitUntilWithRetryOnMainActor` | 同 :139-153 | 15 秒 | Void |
| `waitUntilYielding` | `BefoldApp/befoldTests/TestClock.swift:120-126` | maxYields 100,000 | Void |

いずれも `while` を抜けた後に何もせず return するだけで、`Issue.record` も `#expect` も無い。

## 2. 直後にアサーションが無く、丸ごと silent に浪費し得る箇所

- `BefoldApp/befoldTests/FileWatcherIntegrationTests.swift:86` — `waitUntil { count.get() > beforeDelete }` の直後にアサーションが無い。削除イベントが来なければ 10 秒浪費して素通りし、後続の検証は「削除が反映された前提」で走る
- 同 :27 / :80 / :132 / :183 / :231 — `confirmWatcherArmed`。内部(TestSupport.swift:179-184)の `waitUntilWithRetry` が arm 失敗を検知しないため 1 呼び出しあたり最大 15 秒を silent に消費。さらに :80 / :132 / :183 は戻り値を `_ =` で捨てており、arm 確認が成立したかを誰も見ていない
- `BefoldApp/befoldTests/ViewerStoreIntegrationTests.swift:39-44` — `waitUntilWithRetryOnMainActor` の直後にアサーションが無い

## 3. confirmWatcherArmed の静穏ループにデッドラインが無い

`BefoldApp/befoldTests/TestSupport.swift:185-191` の `while true` は、コールバックが `quiescePeriod`(既定 0.3 秒)ごとに 1 回でも入り続ける状況(CI 高負荷時の debounce 残、他テストの FS 操作)では永久に抜けない。`.timeLimit(.minutes(1))` が最後の砦になっているだけで、その場合 1 テストで 60 秒を焼く。

## 4. .timeLimit の付与範囲が狭い

`.timeLimit` が付いているのは `DebouncerTests` / `FileWatcherIntegrationTests` / `ViewerStoreIntegrationTests` の 3 ファイルのみ。非同期テストは 110 件ある。ポーリングを含むのに `.timeLimit` が無い例: `ViewerWindowControllerToolbarTests.swift:61,:84`、`ViewerStoreFileGoneTests.swift:106,:139,:179,:226,:313,:354`。

## 設計上の推奨

ヘルパー内部でタイムアウト時に `Issue.record(..., sourceLocation:)` を記録する形にすれば、既存の全呼び出し側を一切変更せずに silent green を撲滅できる(`sourceLocation: SourceLocation = #_sourceLocation` を引数に追加)。実装時にこの案と「Bool を返して呼び出し側に検証を強制する」案を比較検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 条件が成立しないままタイムアウトしたポーリングは、必ずテスト失敗として報告される
- [ ] #2 confirmWatcherArmed の静穏待ちが有限時間で必ず終了する
- [ ] #3 ポーリングを含む非同期テストにタイムアウト上限が設定されている
- [ ] #4 既存の全呼び出し箇所が、タイムアウトを検知する形に移行済みである(戻り値を握り潰している箇所が残っていない)
<!-- AC:END -->
