/**
 * 配信面の直近の窓（人間の件数と日次推移）を 1 本のクエリで取り、全期間の経路に重ねる。
 * 全期間の累計と最終発生は routes.ts が持つ。
 */

import { LEGACY_HOST } from '../lib/hosts'
import { JST_DAY_EXPR, jstDaysInWindow, jstWindowStart } from '../lib/jst'
import { NON_HUMAN_MATCH } from './access-class'
import type { RouteTotals } from './routes'
import { DELIVERY_RECENT_DAYS, DELIVERY_WINDOW_DAYS, UNRECORDED_LABEL } from './shared'

/**
 * 経路 1 つぶんの表示用の値。全期間の累計（`RouteTotals`）に窓の件数を重ねたもの。
 *
 * **窓の件数を `RouteTotals` に持たせない。** 累計と最終発生は全期間を走る
 * `eventBreakdowns`、窓は `deliveryWindow` と、取得元が別のクエリになる。
 * 1 つの型にすると `eventBreakdowns` が窓の列を 0 のまま返すことになり、
 * 「まだ埋めていない 0」と「本当に 0 件」が型の上で区別できなくなる。
 */
export type RouteSplit = RouteTotals & {
  /** 直近 `DELIVERY_WINDOW_DAYS` 日の人間の件数。 */
  humanRecent: number
  /** 直近 `DELIVERY_RECENT_DAYS` 日の人間の件数。 */
  humanLatest: number
}

/** 停止判断の対象になる経路の日次推移 1 日ぶん。 */
export type DeliveryDailyPoint = {
  day: string
  legacyHuman: number
  legacyBot: number
  fallbackHuman: number
  fallbackBot: number
}

/** `deliveryWindow` が返す、窓の中だけの人間の件数（経路ラベル → 件数）。 */
type WindowCounts = Map<string, { recent: number; latest: number }>

/** 全期間の集約に、窓の中の人間の件数を重ねる。窓に出てこない経路は 0 のまま。 */
export function withWindowCounts(routes: RouteTotals[], counts: WindowCounts): RouteSplit[] {
  return routes.map((route) => {
    const hit = counts.get(route.label)
    return {
      ...route,
      humanRecent: hit?.recent ?? 0,
      humanLatest: hit?.latest ?? 0,
    }
  })
}

/**
 * 配信面の窓（直近 `DELIVERY_WINDOW_DAYS` 日）を 1 本のクエリで取る。
 *
 * 表の「直近」列と日次推移グラフの両方をこの 1 本から作る。窓の集計を軸ごとに
 * 引くと `query-count.test.ts` の上限に当たるうえ、同じ窓を 2 回定義することになる。
 *
 * **`HUMAN_ONLY` を掛けない。** この面は「人間はもう来ていないが、ロボットが
 * 最終発生を作り続けている」を読むためのもので、ロボット側を落とすと停止判断が
 * できない。`eventBreakdowns` と同じ理由で `NON_HUMAN_MATCH` を式として使い、
 * 人間かどうかは行の属性として返す（analytics.test.ts の自動アクセス除外の検査は
 * この形を除外側として認める）。
 *
 * 日の丸めは `JST_DAY_EXPR`、窓の起点は `jstWindowStart`。どちらも `lib/jst` が
 * 唯一の定義元で、ここに書き下ろさない。
 */
export async function deliveryWindow(
  db: D1Database,
  now: number,
): Promise<{ byHost: WindowCounts; byFallback: WindowCounts; daily: DeliveryDailyPoint[] }> {
  const { results } = await db
    .prepare(
      `SELECT ${JST_DAY_EXPR} AS day,
              host, fallback, COUNT(*) AS count,
              ${NON_HUMAN_MATCH} AS is_non_human
       FROM events
       WHERE timestamp >= ?
       GROUP BY day, host, fallback, is_non_human`,
    )
    .bind(jstWindowStart(now, DELIVERY_WINDOW_DAYS))
    .all<WindowRow>()

  // 短い窓は日付の集合で判定する。ミリ秒で比べ直すと、SQL 側の日の丸めと
  // TS 側の境界がずれたときに列とグラフで食い違う（境界の定義元を 1 つに保つ）。
  const latestDays = new Set(jstDaysInWindow(now, DELIVERY_RECENT_DAYS))

  const byHost: WindowCounts = new Map()
  const byFallback: WindowCounts = new Map()
  const byDay = new Map<string, DeliveryDailyPoint>()

  for (const row of results) {
    const isLatest = latestDays.has(row.day)
    if (row.is_non_human === 0) {
      addWindowCount(byHost, row.host ?? UNRECORDED_LABEL, row.count, isLatest)
      if (row.fallback !== null) addWindowCount(byFallback, row.fallback, row.count, isLatest)
    }

    const point = byDay.get(row.day) ?? {
      day: row.day,
      legacyHuman: 0,
      legacyBot: 0,
      fallbackHuman: 0,
      fallbackBot: 0,
    }
    // 1 件が旧ホストとフォールバックの両方に当たりうる（旧ホストで R2 が外した
    // 場合）。行を排他に振り分けず、両方の系列へ足す。
    if (row.host === LEGACY_HOST) {
      if (row.is_non_human === 1) point.legacyBot += row.count
      else point.legacyHuman += row.count
    }
    if (row.fallback !== null) {
      if (row.is_non_human === 1) point.fallbackBot += row.count
      else point.fallbackHuman += row.count
    }
    byDay.set(row.day, point)
  }

  const daily = jstDaysInWindow(now, DELIVERY_WINDOW_DAYS).map(
    (day) =>
      byDay.get(day) ?? { day, legacyHuman: 0, legacyBot: 0, fallbackHuman: 0, fallbackBot: 0 },
  )

  return { byHost, byFallback, daily }
}

/** `deliveryWindow` が受け取る 1 行。 */
type WindowRow = {
  day: string
  host: string | null
  fallback: string | null
  is_non_human: number
  count: number
}

/** 窓の件数を経路ラベルへ足す。短い窓は長い窓の部分集合なので二重には数えない。 */
function addWindowCount(
  counts: WindowCounts,
  label: string,
  count: number,
  isLatest: boolean,
): void {
  const hit = counts.get(label) ?? { recent: 0, latest: 0 }
  hit.recent += count
  if (isLatest) hit.latest += count
  counts.set(label, hit)
}
