---
id: TASK-552
title: ダッシュボードのクエリ本数テストに SSE の周期コストを載せ、内訳コメントの実装ずれを直す
status: To Do
assignee: []
created_date: '2026-08-25 02:00'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 800000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/test/query-count.test.ts` の退行検知が、概要面の実際のコストを測っていない。

## 現状（2026-08-25 にコード確認・TASK-551 の設計レビューで発見）

### 1. SSE の周期コストが測られていない

`site/src/routes/dashboard.tsx` の `/dashboard/stream` は、新着イベントがあった周期で `renderOverviewSections(await summarizeOverview(db, Date.now()))` を丸ごと呼び直す。`POLL_INTERVAL_MS = 2500`、`MAX_STREAM_MS = 10 * 60 * 1000`。加えて毎周期 `maxEventId` と `eventsAfter` を引く。

つまり**概要面のクエリ 1 本は「面を開いたとき 1 回」ではなく「ブラウザを開いている間 2.5 秒ごと」のコスト**であり、他の面の 1 本とは重みが違う。

一方 `query-count.test.ts` の `SUMMARIZERS.overview` は `summarizeOverview(db, NOW)` を **1 回だけ**呼んで `D1Database.prepare` の回数を数える。`MAX_QUERIES_PER_PAGE = 8` に対し概要面は 4 本で、枠が空いているように見える。**この枠は「足してよい」という意味には読めないが、テストにはそう読めてしまう。**

### 2. コメントの内訳が実装とずれている

`MAX_QUERIES_PER_PAGE` の doc コメントは面ごとの内訳を「overview 4 本 / users 3 本 / traffic 7 本 / delivery 1 本 / events 1 本」、`MAX_QUERIES_TOTAL` の doc は「現在の合計は 17 本」と書いている。

コード実測（2026-08-25）:

| 面 | コメント | 実測 | 内訳（実測） |
| --- | --- | --- | --- |
| overview | 4 | 4 | cumulativeTotals / todayTotals / dailySeries / recentEvents |
| users | 3 | **4** | dailySeries / hourlyDistribution / runningVersionBreakdown / updateAdoption |
| traffic | 7 | **6** | cumulativeTotals / breakdown(country) / referrerBreakdowns / trafficSplit / kindBreakdowns(=metricBreakdowns 1 本) / eventBreakdowns |
| delivery | 1 | 1 | eventBreakdowns |
| events | 1 | 1 | eventPage |
| 合計 | 17 | **16** | |

上限（8 / 20）自体は実測を上回っているのでテストは緑のまま通る。**内訳が実装と食い違っていても誰も気づかない形**になっている。履歴コメントに残る「13」「14」という数値も、面を分ける前の `MAX_QUERIES_PER_PAGE` の値であって現在の 8 とは無関係だが、並べて書かれているため読み解きづらい。

## やること

1. 概要面の SSE 周期コストが退行検知に載る形にする。何を測るかは実装前に決めること（下記）。
2. コメントの内訳を実測に合わせる。**書き写しではなく、テスト自体が実測値を出力するか、ずれたら落ちる形にできないか**を先に検討する（数字を手で書き直すだけでは同じずれが再発する）。

## 着手前に決めること

- **SSE のコストを何で表現するか。** 「1 回の周期で発行されるクエリ本数」（`maxEventId` + `eventsAfter` + 新着があれば `summarizeOverview` = 最大 6 本）に上限を置くのが素直だが、これは既存の「面ごとの上限」とは別の軸になる。既存の `MAX_QUERIES_PER_PAGE` に相乗りさせるのか、`MAX_QUERIES_PER_STREAM_CYCLE` を別に立てるのかを決めること。
- **概要面のクエリを「他の面より重い」と表現するか。** 重み付き上限にすると読み手に意図が伝わる一方、テストの意味が「本数の退行検知」から離れる。`docs/dev/development.md` が定める「上限を上げるのではなく既存クエリへ列を足すか UNION ALL で束ねる」という方針との整合を確認すること。
- **内訳コメントをテストから導けるか。** 面ごとの実測本数を `expect` で固定すれば、コメントを消してテストが内訳の定義元になる。ただし面を触るたびに期待値の更新が要るので、上限だけを見る現在の方針との得失を比べること。

## 背景

TASK-551（ダッシュボードの主指標の変更）の設計レビューで、概要面へクエリを足してよいかを検討した際に発見した。TASK-551 自体はクエリ 0 本増で収めたため、この件で悪化はしていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 概要面が SSE で 2.5 秒ごとに再集計されるコストが、退行検知の対象に入っている
- [ ] #2 クエリ本数の内訳の記述が実装と一致している（users 4 / traffic 6 / 合計 16）
- [ ] #3 内訳が再びずれたときに気づける形になっている（手で書き写した数値がテストのどこにも残っていない、または、ずれたら落ちる）
- [ ] #4 上の「着手前に決めること」3 点の結論が Implementation Notes に残っている
- [ ] #5 site の vitest が通る
<!-- AC:END -->
