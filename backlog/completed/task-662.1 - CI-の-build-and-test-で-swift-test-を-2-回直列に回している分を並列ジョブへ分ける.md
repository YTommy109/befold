---
id: TASK-662.1
title: CI の build-and-test で swift test を 2 回直列に回している分を並列ジョブへ分ける
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 04:29'
updated_date: '2026-09-29 04:52'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: high
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`.github/workflows/ci.yml` の build-and-test は、通常の `swift test` のあとに `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 付きの `swift test` をもう 1 周同じジョブで回している。手元で 36 秒 + 40 秒、CI では 1 周 136 秒規模の実測がある（`BefoldTestSupport/Waiting.swift` の doc）ため、PR のクリティカルパスが 1 周分まるごと伸びている。

プール幅 1 のランは TASK-424 / 427 / 516 で 3 度再発を捕まえた検知なので、PR から外す（nightly へ移す）のではなく、検知を保ったまま待ち時間だけ消す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 プール幅 1 のランが通常ランと並列に走る（別ジョブまたは matrix）
- [x] #2 プール幅 1 のランは引き続き PR で走り、落ちれば PR が落ちる
- [x] #3 変更前後の PR の build-and-test 所要時間（ジョブ開始から両ラン完了まで）を Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. build-and-test を matrix（pool: default / strict）に分け、2 ランを別ランナーで並列にする
2. concurrency group に matrix 値を含める（含めないと 2 レッグが互いをキャンセルする）
3. SwiftFormat 検査は default レッグだけで回す
4. PR を出し、変更前後の所要時間を Notes に記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 所要時間（ジョブ開始から両ラン完了まで）
変更前（直近の成功 PR 5 本, run 36417677490 / 36310949444 / 36288303391 / 36224291359 / 36144241893）: 8m44s / 7m13s / 7m18s / 9m18s / 9m20s。うち幅 1 のランは 1m46s〜2m22s。
変更後（PR #702, run 36523026526）: 両レッグ 04:45:31 開始、strict 完了 04:49:56（4m25s）、default 完了 04:51:26（5m55s）→ 5m55s。

## 判断
- matrix の concurrency group に matrix.pool を含めた。含めないと 2 レッグが同じグループに入り相互にキャンセルする
- 環境変数は値ではなく有無で切り替えた（default レッグには定義自体を渡さない。libdispatch が '0' をどう解釈するかに依存しないため）
- SwiftFormat 検査は default レッグのみ。クリティカルパスは default（SwiftFormat 72s + テスト 176s）側に移った
- strict レッグのログで export LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 の実行と 2093 件 pass を確認
- 落ちたときの赤化: strict レッグは PR の独立したチェック（build-and-test (strict)）として出ており fail-fast: false。意図的に落として確かめてはいない
- 起票コミットが main に入っていなかったため PR #702 に cherry-pick で同梱
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ci.yml の build-and-test を matrix（pool: default / strict）へ分け、通常ランとプール幅 1 のランを別ランナーで並列化した。幅 1 のランは引き続き PR の独立チェックとして走る。PR #702 の CI で両レッグ pass、ジョブ開始から両ラン完了まで 5m55s（変更前 7m13s〜9m20s）。native-app-design.md の担保の記述も追随。
<!-- SECTION:FINAL_SUMMARY:END -->
