import { env } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

import type { DashboardPageKey } from '../src/analytics'
import {
  DASHBOARD_PAGES,
  eventPage,
  summarizeDelivery,
  summarizeOverview,
  summarizeTraffic,
  summarizeUsers,
} from '../src/analytics'
import { runStreamCycle } from '../src/routes/dashboard'

/**
 * 1 つの面を開いたときに発行される D1 クエリ本数の上限。
 *
 * この上限の目的は性能ではなく、「指標を 1 つ足すたびにクエリが 1 本増える」形への
 * 退行検知（TASK-423 の前は 1 ページ 19 本だった）。面を分ける前は 1 ページ 13 本で、
 * 上限もその 13 だった。履歴: TASK-423 で 19 → 13、TASK-488.2 で 13 → 14、
 * TASK-488.3 は 14 のまま（同じ GROUP BY へ列を足した）、TASK-490 で 14 → 13
 * （区分を行に持たせて ROW_NUMBER の窓で切った）、TASK-491.2 は 13 のまま
 * （os / as_org を UNION ALL で 1 本に畳んで枠を空けた）、TASK-494 も 13 のまま
 * （既存の日別推移クエリの SELECT 句へ COUNT(DISTINCT CASE WHEN ...) を並べた）。
 * TASK-492 でイベント面を足し、面ごとの上限を 8 に切り直した。
 *
 * **面ごとの実本数は下の `EXPECTED_QUERIES` が持つ。** 内訳を doc コメントへ
 * 書き写すと実装とずれても誰も気づかないため（TASK-552 の時点で
 * users が 3 本と書かれていたが実際は 4 本だった）、数値は expect で固定して、ずれたらテストが落ちる形にしてある。
 */
const MAX_QUERIES_PER_PAGE = 8

/**
 * 全ページ合計の上限。
 *
 * **ページごとの上限だけでは、面を増やすことで上限を回避できてしまう。**
 * 合計にも上限を置くことで、退行検知としての意味を保つ。
 */
const MAX_QUERIES_TOTAL = 20

/**
 * SSE の 1 ポーリング周期（`POLL_INTERVAL_MS` = 30 秒）で発行される本数の上限。
 *
 * **概要面のクエリは「面を開いたとき 1 回」ではない。** ダッシュボードを開いている
 * 間ずっと `POLL_INTERVAL_MS` ごとに `runStreamCycle` が走るため、他の面の 1 本とは
 * 重みが違う。
 * 面ごとの上限に相乗りさせると軸が混ざる（片方は 1 回、片方は毎秒 0.4 回）ので、
 * 別の上限として立てている。新着が無い周期でも `maxEventId` と `eventsAfter` の
 * 2 本は必ず引くため、タブを 1 つ開いたままにするだけで 4 本/分が流れる
 * （間隔を 2.5 秒から広げる前は 48 本/分だった = TASK-556）。
 * ここへクエリを足すことの重さを、面へ 1 本足すのと同じに見せないための上限。
 */
const MAX_QUERIES_PER_STREAM_CYCLE = 6

/** prepare の呼び出し回数を数えるためだけの薄いラッパ。 */
function countingDb(db: D1Database): { db: D1Database; count: () => number } {
  let calls = 0
  const proxy = new Proxy(db, {
    get(target, property, receiver) {
      const value = Reflect.get(target, property, receiver)
      if (property !== 'prepare' || typeof value !== 'function') return value
      return (query: string) => {
        calls += 1
        return value.call(target, query)
      }
    },
  })

  return { db: proxy as D1Database, count: () => calls }
}

const NOW = Date.parse('2026-08-08T03:00:00Z')

/**
 * 面ごとの集計。**`DASHBOARD_PAGES` と同じキーで網羅する。**
 *
 * `Record<DashboardPageKey, ...>` なので、面を足してここへ書き忘れると型で落ちる。
 * これが「上限テストの列挙から漏れた面」を作れなくしている担保。
 */
const SUMMARIZERS: Record<DashboardPageKey, (db: D1Database) => Promise<unknown>> = {
  overview: async (db) => await summarizeOverview(db, NOW),
  users: async (db) => await summarizeUsers(db, NOW),
  traffic: async (db) => await summarizeTraffic(db),
  delivery: async (db) => await summarizeDelivery(db, NOW),
  events: async (db) => await eventPage(db),
}

/**
 * 面ごとの実クエリ本数。**この表が内訳の定義元**で、doc コメントには書かない。
 *
 * 上限（`MAX_QUERIES_PER_PAGE`）だけを見ていると、枠が空いている面へ黙って
 * 1 本足しても緑のまま通る。実数を固定してあるので、増えても減っても落ちる。
 * 意図して増減させたときはこの表を更新する（更新の差分がレビューに出る）。
 *
 * - overview 4: cumulativeTotals / todayTotals / dailySeries / recentEvents
 * - users 4: dailySeries / hourlyDistribution / runningVersionBreakdown / updateAdoption
 * - traffic 7: cumulativeTotals / breakdown(country) / referrerBreakdowns /
 *   trafficSplit 2 本（総数・区分別内訳）/ 指標別内訳 1 本（OS 別・接続元組織別・
 *   バージョン別を 1 本にまとめてあり、指標の数にも軸の数にも依らない）/
 *   eventBreakdowns
 * - delivery 2: eventBreakdowns / deliveryWindow（直近 30 日の窓と日次推移）
 * - events 1: eventPage（次のページの有無も同じクエリで確定させる）
 */
const EXPECTED_QUERIES: Record<DashboardPageKey, number> = {
  overview: 4,
  users: 4,
  traffic: 7,
  delivery: 2,
  events: 1,
}

/** 新着イベントの有無で周期のコストが変わるので、行を 1 件入れて「あり」を作る。 */
async function insertEvent(): Promise<void> {
  await env.DB.prepare(
    "INSERT INTO events (timestamp, kind, ua_summary) VALUES (?, 'visit', 'Safari / macOS')",
  )
    .bind(NOW)
    .run()
}

describe('ダッシュボードのクエリ本数', () => {
  it.each(DASHBOARD_PAGES.map((page) => [page.key, page.title] as const))(
    '%s（%s）は実測どおりの本数で、1 ページ分の上限を超えない',
    async (key) => {
      const { db, count } = countingDb(env.DB)

      await SUMMARIZERS[key](db)

      expect(count()).toBe(EXPECTED_QUERIES[key])
      expect(count()).toBeLessThanOrEqual(MAX_QUERIES_PER_PAGE)
    },
  )

  it('全ページの合計が上限を超えない（面を増やして上限を回避できない）', async () => {
    const { db, count } = countingDb(env.DB)

    for (const page of DASHBOARD_PAGES) {
      // 面ごとに順に数える。並行にしても合計は変わらないが、
      // どの面で増えたかを追えるよう順に流す。
      await SUMMARIZERS[page.key](db)
    }

    // 合計も内訳の総和と一致していること（どこかの面だけ二重に数えていない）。
    const expectedTotal = Object.values(EXPECTED_QUERIES).reduce((sum, n) => sum + n, 0)
    expect(count()).toBe(expectedTotal)
    expect(count()).toBeLessThanOrEqual(MAX_QUERIES_TOTAL)
  })

  it('面の一覧とルートの生成元が一致している', () => {
    expect(DASHBOARD_PAGES.map((page) => page.key)).toEqual(Object.keys(SUMMARIZERS))
  })

  describe('SSE の 1 ポーリング周期', () => {
    it('新着が無い周期はカーソルの 2 本だけで、再集計しない', async () => {
      const { db, count } = countingDb(env.DB)

      const cycle = await runStreamCycle(db, 0)

      expect(cycle.summaryHtml).toBeNull()
      expect(count()).toBe(2)
      expect(count()).toBeLessThanOrEqual(MAX_QUERIES_PER_STREAM_CYCLE)
    })

    it('新着がある周期はカーソル 2 本 + 概要面の再集計まで引く', async () => {
      await insertEvent()
      const { db, count } = countingDb(env.DB)

      const cycle = await runStreamCycle(db, 0)

      expect(cycle.summaryHtml).not.toBeNull()
      // 概要面を開き直すのと同じコストが、周期ごとに乗る。
      expect(count()).toBe(2 + EXPECTED_QUERIES.overview)
      expect(count()).toBeLessThanOrEqual(MAX_QUERIES_PER_STREAM_CYCLE)
    })
  })
})
