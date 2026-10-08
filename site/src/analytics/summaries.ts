/**
 * 面ごとの集計の入口。routes/dashboard.tsx がこれを呼ぶ。
 * クエリを組み合わせて *Summary を作るだけで、SQL は書かない。
 */

import {
  type KindBreakdown,
  type TrafficSplit,
  breakdown,
  kindBreakdowns,
  referrerBreakdowns,
  trafficSplit,
} from './breakdowns'
import { deliveryWindow, withWindowCounts } from './delivery'
import type { DeliveryDailyPoint, RouteSplit } from './delivery'
import { type RecentEvent, recentEvents } from './events'
import { type VisitBreakdowns, eventBreakdowns } from './routes'
import { type Count, DAILY_WINDOW_DAYS } from './shared'
import type { RunningVersions } from './sources'
import {
  type CumulativeTotals,
  type DailyPoint,
  type HourlyPoint,
  type TodayTotals,
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  todayTotals,
} from './totals'
import { runningVersionBreakdown, updateAdoption } from './users'
import type { AdoptionCurve, UpdateConversion } from './users'

/** 概要面: 全期間と当日の総数、日毎の推移、最新イベント。 */
export type OverviewSummary = {
  windowDays: number
  cumulative: CumulativeTotals
  today: TodayTotals
  daily: DailyPoint[]
  recent: RecentEvent[]
}

/** 利用者面: 母集団別の日次ユニーク、稼働バージョン、時間帯分布。 */
export type UsersSummary = {
  windowDays: number
  daily: DailyPoint[]
  hourly: HourlyPoint[]
  runningVersions: RunningVersions
  conversion: UpdateConversion
  adoption: AdoptionCurve[]
}

/** 流入面: どこから来て何をしたか。全期間の累計で見る。 */
export type TrafficSummary = {
  byCountry: Count[]
  byReferrer: Count[]
  /** ダウンロード（LP）だけに絞った参照元。`?ref=` が運ぶ「ダウンロードが始まった面」。 */
  byDownloadReferrer: Count[]
  traffic: TrafficSplit
  visits: VisitBreakdowns
  perKind: KindBreakdown[]
}

/** 配信面: 配布ホストと旧経路・フォールバック。 */
export type DeliverySummary = {
  hosts: RouteSplit[]
  fallbacks: RouteSplit[]
  dailyRoutes: DeliveryDailyPoint[]
}

/**
 * 概要面の集計（4 クエリ）。
 *
 * SSE の再描画もこれを使う。面を分ける前は 13 クエリすべてを引き直していた。
 */
export async function summarizeOverview(db: D1Database, now: number): Promise<OverviewSummary> {
  const [cumulative, today, daily, recent] = await Promise.all([
    cumulativeTotals(db),
    todayTotals(db, now),
    dailySeries(db, now),
    recentEvents(db),
  ])

  return { windowDays: DAILY_WINDOW_DAYS, cumulative, today, daily, recent }
}

/** 利用者面の集計（3 クエリ）。 */
export async function summarizeUsers(db: D1Database, now: number): Promise<UsersSummary> {
  const [daily, hourly, runningVersions, updates] = await Promise.all([
    dailySeries(db, now),
    hourlyDistribution(db, now),
    runningVersionBreakdown(db, now),
    updateAdoption(db, now),
  ])

  return {
    windowDays: DAILY_WINDOW_DAYS,
    daily,
    hourly,
    runningVersions,
    conversion: updates.conversion,
    adoption: updates.adoption,
  }
}

/**
 * 流入面の集計（8 クエリ）。
 *
 * 参照元は「全体」と「ダウンロード（LP）だけ」の 2 つの母集団を出すが、
 * `referrerBreakdowns` が 1 本にまとめているのでクエリ本数は増えない。
 *
 * `perKind` の総数は全期間の累計から取るため、この面も cumulativeTotals を引く。
 * ua_summary の内訳は AI クローラ（GPTBot / ClaudeBot 等）の到来量を実測する
 * ために持つ。TASK-360 で見送った llms.txt の要否判断に使う。データセンター
 * 区分の内訳は接続元組織で、除外した量が画面から消えないようにするもの（ADR 0008）。
 */
export async function summarizeTraffic(db: D1Database): Promise<TrafficSummary> {
  const [cumulative, byCountry, referrers, traffic, breakdowns, breakdownAxes] = await Promise.all([
    cumulativeTotals(db),
    breakdown(db, 'country'),
    referrerBreakdowns(db),
    trafficSplit(db),
    kindBreakdowns(db),
    eventBreakdowns(db),
  ])

  return {
    byCountry,
    byReferrer: referrers.all,
    byDownloadReferrer: referrers.download,
    traffic,
    visits: breakdownAxes.visits,
    // 要素数は指標の数（KIND_LABELS）に固定で、ここでの spread が効いてくる規模に
    // ならない。Object.assign へ書き換えると読みにくくなるだけなので許す。
    // oxlint-disable-next-line oxc/no-map-spread
    perKind: breakdowns.map((entry) => ({ ...entry, total: cumulative.counts[entry.kind] })),
  }
}

/**
 * 配信面の集計（2 クエリ）。
 *
 * 窓の長さは戻り値に載せず、表示側が `DELIVERY_WINDOW_DAYS` /
 * `DELIVERY_RECENT_DAYS` を直接読む。面ごとの集計を 1 つへ畳んで検証している
 * テスト（analytics.test.ts の `summarizeAll`）で `windowDays` が利用者面の 14 と
 * 衝突し、片方が黙って上書きされるため。
 *
 * 全期間の累計と最終発生は `eventBreakdowns`、直近の窓と日次推移は
 * `deliveryWindow` が持つ。**累計だけでは停止判断ができない**ため両方を引く——
 * 累計は一度発生すると二度と減らず、クローラの一斉巡回が残した数がいつまでも
 * 「まだ落ちている」ように見える（実測 2026-09-04: GitHub フォールバック 266 件の
 * うち 262 件が 8/19-8/26 のボット由来）。
 */
export async function summarizeDelivery(db: D1Database, now: number): Promise<DeliverySummary> {
  const [breakdownAxes, window] = await Promise.all([eventBreakdowns(db), deliveryWindow(db, now)])

  return {
    hosts: withWindowCounts(breakdownAxes.byHost, window.byHost),
    fallbacks: withWindowCounts(breakdownAxes.byFallback, window.byFallback),
    dailyRoutes: window.daily,
  }
}
