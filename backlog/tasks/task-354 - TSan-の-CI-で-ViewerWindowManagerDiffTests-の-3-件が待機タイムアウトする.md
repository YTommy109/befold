---
id: TASK-354
title: TSan の CI で ViewerWindowManagerDiffTests の 3 件が待機タイムアウトする
status: To Do
assignee: []
created_date: '2026-08-07 14:14'
labels:
  - test
  - flaky
  - ci
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/31173231496'
priority: high
type: bug
ordinal: 613000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

main の CI（run 31173231496, v1.12.2 の bump コミット, 2026-08-07 11:18）の thread-sanitizer ジョブで、`ViewerWindowManagerDiffTests` の 3 件が同時に失敗した。

```text
✘ "片方のウィンドウのトグルが全ウィンドウの差分に届く"       :58   133.668s
✘ "ウィンドウを閉じても他窓の差分取得に影響しない"           :187  133.808s
✘ "同じファイルを 2 窓で開いても git diff は 1 回に合流する"  :138  146.326s
```

3 件とも失敗行は `waitUntilOnMainActor(timeout: testTimeout(fallback: 60))` の呼び出し（`ViewerWindowManagerDiffTests.swift:58` / `:138` / `:187`）で、**回数の不一致ではなく待機のタイムアウト**。

## TASK-346 との違い

TASK-346 の失敗は `Expectation failed: (reader.callCount → 3) == (before + 1 → 2)` という回数の算術で、合流が壁時計の重なりに依存していたことが原因だった。これは構造修正で解消し、その後の main CI 3 回（run 31145812149 / 31152119577 / 31158346419）で thread-sanitizer は成功している。本件は失敗の形が違うため別タスクとする。

## 手がかり（未確認の仮説を含む）

- 全体実行が 150.9 秒なのに個々の待機が 133〜146 秒 — つまり**このスイートの差分がテスト実行のほぼ全期間にわたって着地していない**。CI は `BEFOLD_TEST_TIMEOUT_SECONDS=120` を設定済み（ci.yml:93）で、その予算を使い切っている。
- TASK-327 の実測「full suite 実行中はメインアクターが 5.1〜8.3 秒到達不能、失敗回は 15 秒予算内に一度も到達しなかった」の延長線にある可能性が高い。ただし 120 秒を使い切るのは飢餓の程度として大きく、**差分が本当に着地していない（取得が起きていない／結果が書き戻されていない）可能性を先に潰すこと**。
- 未確認: 直前のマージ（PR #433 の `fix(gate): 差分の比較基準をサイドバーのバッジと揃える` = 723c385、PR #434 = 3f4449d）との関係。#433 / #434 の CI では thread-sanitizer は成功しているため、単発の遅さか、bump コミットで初めて条件が揃ったかは切り分けが必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3 件が待機タイムアウトする原因を、飢餓か着地漏れかまで切り分けて実測で特定している
- [ ] #2 thread-sanitizer 付きの実行で 3 件が 10 回連続して失敗しない
- [ ] #3 待機の判定が壁時計の予算切れに左右されにくい形になっている（予算を伸ばすだけの対処にしない）
<!-- AC:END -->
