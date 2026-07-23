---
id: TASK-116.6
title: thread-sanitizer ジョブの慢性的な失敗を解消する
status: To Do
assignee: []
created_date: '2026-07-23 23:19'
labels:
  - test
  - ci
dependencies:
  - TASK-116.5
parent_task_id: TASK-116
priority: medium
ordinal: 30600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブが main push / nightly でほぼ毎回失敗しており、常時赤のためシグナルとして機能していない。

## 実測

直近の CI 失敗 8 件のうち 7 件が thread-sanitizer ジョブ(残り 1 件は build-and-test)。原因は毎回同一:

```
✘ Test deletingWatchedFileFiresOnFileGone() recorded an issue at
  ViewerStoreIntegrationTests.swift:20:6: Time limit was exceeded: 60.000 seconds
✘ Test run with 590 tests in 74 suites failed after 74.287 seconds with 1 issue
```

同じ run で `truncatedScript は failed=true を渡せる` という純粋ロジックのテストが 61 秒かかって pass しており、TSan 下で並列実行が極端に不均衡になっている(スイート全体は 74 秒で終わる)。単純なタイムアウト値の引き上げではなく、TSan 下で当該テストが何を待っているのかを先に切り分けること。

## 経緯

TASK-11(Done)で同種の TSan 失敗を `BEFOLD_TEST_TIMEOUT_SECONDS` の尊重漏れ修正により解消した実績がある。今回は別のテストでの再発であり、ワークフロー側は既に thread-sanitizer ジョブに `BEFOLD_TEST_TIMEOUT_SECONDS: 120` を設定済み(`.github/workflows/ci.yml`)。それでも `.timeLimit(.minutes(1))` の 60 秒上限に先に当たっているため、環境変数だけでは解決しない構造になっている点に注意。

## 判断してほしいこと

TSan を回し続ける価値があるか。常時赤を放置するくらいなら、対象テストを TSan 実行から除外して残りを緑に保つ方がシグナルとして有用な可能性がある。実装前にこの選択を明示的に検討し、判断理由を記録すること。

## 依存

TASK-116.5(ポーリングヘルパーの silent timeout 撲滅)を先に済ませると、TSan 下で「何が待たれているか」が失敗メッセージから直接分かるようになるため、切り分けが容易になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 thread-sanitizer ジョブが main push / nightly で安定して結果を返す(常時赤ではない)
- [ ] #2 deletingWatchedFileFiresOnFileGone が TSan 下で時間超過しない、または対象から意図的に除外され理由が記録されている
- [ ] #3 TSan を継続する/縮小する の判断理由がタスクに記録されている
<!-- AC:END -->
