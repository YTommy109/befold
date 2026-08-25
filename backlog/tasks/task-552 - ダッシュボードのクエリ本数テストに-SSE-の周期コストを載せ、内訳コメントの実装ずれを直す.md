---
id: TASK-552
title: ダッシュボードのクエリ本数テストに SSE の周期コストを載せ、内訳コメントの実装ずれを直す
status: Done
assignee: []
created_date: '2026-08-25 02:00'
updated_date: '2026-08-25 02:18'
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
- [x] #1 概要面が SSE で 2.5 秒ごとに再集計されるコストが、退行検知の対象に入っている
- [x] #2 クエリ本数の内訳の記述が実装と一致している（起票時の実測は誤りで、正しくは users 4 / traffic 7 / 合計 17）
- [x] #3 内訳が再びずれたときに気づける形になっている（手で書き写した数値がテストのどこにも残っていない、または、ずれたら落ちる）
- [x] #4 上の「着手前に決めること」3 点の結論が Implementation Notes に残っている
- [x] #5 site の vitest が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前に決めたこと（AC#4）

**1. SSE のコストを何で表現するか → 面ごとの上限とは別の軸として `MAX_QUERIES_PER_STREAM_CYCLE = 6` を立てた。**
面ごとの上限（1 回のページ表示）と周期コスト（2.5 秒ごと）は単位が違い、同じ上限へ相乗りさせると
「面へ 1 本足す」と「周期へ 1 本足す」が同じ重さに見える。周期側は 1 本足すと 24 本/分増える。
別定数にして doc コメントで重みの違いを書いた。

**2. 概要面のクエリを「他の面より重い」と表現するか → 重み付き上限にはしない。**
重みを掛けると「本数の退行検知」というテストの意味が薄れる。代わりに周期コストを
独立したテストとして測り、doc コメントで 48 本/分という実数を書いた。
`docs/dev/development.md` の「上限を上げず既存クエリへ列を足すか UNION ALL で束ねる」方針とは
矛盾しない（上限を新設しただけで、既存の上限は据え置き）。

**3. 内訳コメントをテストから導けるか → テスト内の `EXPECTED_QUERIES` を定義元にした。**
面ごとの実本数を `toBe` で固定し、合計もその総和との一致を見る。上限（8 / 20）だけを見る
現在の方針だと、枠が空いている面へ黙って 1 本足しても緑のまま通る。面を触るたびに期待値の
更新が要るが、その差分がレビューに出ることのほうが価値が高いと判断した。

## 起票時の実測が誤っていた

Description の表は traffic 6 / 合計 16 としていたが、実測（vitest）では **traffic 7 / 合計 17**。
`trafficSplit` が prepare を 2 本発行する（総数・区分別内訳）ことを数え落としていた。
実際にずれていたのは users だけ（コメント 3 本 / 実測 4 本 = updateAdoption の数え落とし）。

## 実装

- `site/src/routes/dashboard.tsx`: `/stream` のポーリング 1 周期分の D1 アクセスを
  `runStreamCycle(db, lastId)` として切り出し export した（ルート本体は enqueue だけを持つ）。
  テストから実コードパスを呼べるようにするための抽出で、挙動は変えていない。
- `site/test/query-count.test.ts`: `EXPECTED_QUERIES` で面ごとの実本数を固定。
  SSE 周期のテストを 2 件追加（新着なし = 2 本・再集計しない / 新着あり = 2 + 概要面 4 = 6 本）。

## 検証

- `npx vitest run`（site）: 13 files / 427 tests すべて緑。
- 退行検知が効くことの確認: `runStreamCycle` に `maxEventId` の呼び出しを 1 本足すと、
  周期テスト 2 件が `expected 3 to be 2` / `expected 7 to be 6` で落ちる（確認後に戻した）。
- `npm run lint` / `npm run format:check` ともにクリーン。

## 派生

SSE をポーリングではなく Durable Object 経由の push にできないかという指摘を受け、
TASK-554 として別途起票した（本タスクの計測がその効果測定の土台になる）。
<!-- SECTION:NOTES:END -->
