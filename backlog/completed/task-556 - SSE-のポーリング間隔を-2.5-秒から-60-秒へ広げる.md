---
id: TASK-556
title: SSE のポーリング間隔を 2.5 秒から 30 秒へ広げる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-25 07:17'
updated_date: '2026-08-25 07:43'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 804000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アクセス数が少ない現状に対してポーリングが細かすぎるため、`POLL_INTERVAL_MS` を 2500 → 30000 にする（ユーザー判断、2026-08-25）。

## 効果と代償

- アイドル時の D1 クエリ: 48 本/分 → **4 本/分**（1 周期 2 本は変わらず、周期数が 24 回/分 → 2 回/分）
- 1 接続（`MAX_STREAM_MS` = 10 分）あたりの周期数: 240 → 20
- 代償: 画面の更新が最大 30 秒遅れる。周期末の `event: cursor` が接続維持を兼ねている（TASK-555）ため、**この間隔はそのまま keep-alive の間隔でもある**。一般的なプロキシのアイドルタイムアウト（100 秒前後）に対しては十分な余裕がある

## 反映先

定数のほか、間隔と「48 本/分」を書いている箇所が 3 つある（`site/test/query-count.test.ts` の doc、`docs/dev/development.md`、`site/src/routes/dashboard.tsx` の doc）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 POLL_INTERVAL_MS が 60000 になっている
- [x] #2 間隔と本数を書いた doc（query-count.test.ts / development.md / dashboard.tsx）が実装と一致している
- [x] #3 site の vitest が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`POLL_INTERVAL_MS` を 2500 → 30000 にし、間隔と本数を書いていた doc 3 箇所（`site/src/routes/dashboard.tsx` の定数 doc、`site/test/query-count.test.ts`、`docs/dev/development.md`）を実装に合わせた。数値の重複を減らすため、doc 側は可能な箇所を `POLL_INTERVAL_MS` の参照に置き換えている（間隔を次に変えるときに直す場所を減らすため）。

**周期末の `event: cursor` が接続維持を兼ねている**（TASK-555）ので、この間隔はそのまま keep-alive の間隔でもある。その旨を定数の doc に書いた。30 秒なら一般的なプロキシのアイドルタイムアウト（100 秒前後）に対して余裕がある。

## 実測

- `npm test`（site）: 13 files / 431 tests 通過。`npm run lint`（--type-aware）・`format:check`・`markdownlint-cli2` すべてゼロ件
- SSE のテストは 1 周期目（接続直後に即実行される）だけを読む形なので、間隔を広げてもテスト時間は伸びない（dashboard.test.ts は 1.37 秒のまま）

## 未検証

実ブラウザでの体感（更新が最大 30 秒遅れること）はデプロイ後に確認が要る。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
POLL_INTERVAL_MS を 2500 → 30000 にし、アイドル時の D1 クエリを 48 本/分から 4 本/分にした。間隔と本数を書いていた doc 3 箇所を実装に合わせ、可能な箇所は定数参照へ置き換えた。site の vitest 431 件通過、テスト時間も変わらず（1 周期目しか読まないため）。
<!-- SECTION:FINAL_SUMMARY:END -->
