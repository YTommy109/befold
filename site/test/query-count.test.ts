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

/**
 * 1 つの面を開いたときに発行される D1 クエリ本数の上限。
 *
 * 内訳:
 * - overview 4 本: cumulativeTotals / todayTotals / dailySeries / recentEvents
 * - users 3 本: dailySeries / hourlyDistribution / runningVersionBreakdown
 * - traffic 7 本: cumulativeTotals / breakdown 2 本（country・referrer）/
 *   trafficSplit 2 本（総数・区分別内訳）/ 指標別内訳 1 本（OS 別・接続元組織別・
 *   バージョン別を 1 本にまとめてあり、指標の数にも軸の数にも依らない）/
 *   eventBreakdowns 1 本
 * - delivery 1 本: eventBreakdowns
 * - events 1 本: eventPage（次のページの有無も同じクエリで確定させる）
 *
 * この上限の目的は性能ではなく、「指標を 1 つ足すたびにクエリが 1 本増える」形への
 * 退行検知（TASK-423 の前は 1 ページ 19 本だった）。面を分ける前は 1 ページ 13 本で、
 * 上限もその 13 だった。履歴: TASK-423 で 19 → 13、TASK-488.2 で 13 → 14、
 * TASK-488.3 は 14 のまま（同じ GROUP BY へ列を足した）、TASK-490 で 14 → 13
 * （区分を行に持たせて ROW_NUMBER の窓で切った）、TASK-491.2 は 13 のまま
 * （os / as_org を UNION ALL で 1 本に畳んで枠を空けた）、TASK-494 も 13 のまま
 * （既存の日別推移クエリの SELECT 句へ COUNT(DISTINCT CASE WHEN ...) を並べた）。
 * TASK-492 でイベント面を足して合計 16 → 17。TASK-506 で 17 → 16
 * （バージョン別を単独クエリから指標別内訳の軸へ畳んだ）。
 */
const MAX_QUERIES_PER_PAGE = 8

/**
 * 全ページ合計の上限。
 *
 * **ページごとの上限だけでは、面を増やすことで上限を回避できてしまう。**
 * 合計にも上限を置くことで、退行検知としての意味を保つ。現在の合計は 17 本。
 */
const MAX_QUERIES_TOTAL = 20

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
  delivery: async (db) => await summarizeDelivery(db),
  events: async (db) => await eventPage(db),
}

describe('ダッシュボードのクエリ本数', () => {
  it.each(DASHBOARD_PAGES.map((page) => [page.key, page.title] as const))(
    '%s（%s）は 1 ページ分の上限を超えない',
    async (key) => {
      const { db, count } = countingDb(env.DB)

      await SUMMARIZERS[key](db)

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

    expect(count()).toBeLessThanOrEqual(MAX_QUERIES_TOTAL)
  })

  it('面の一覧とルートの生成元が一致している', () => {
    expect(DASHBOARD_PAGES.map((page) => page.key)).toEqual(Object.keys(SUMMARIZERS))
  })
})
