/**
 * ダッシュボード向けの集計。規模が小さいため都度 GROUP BY で算出する。
 *
 * このファイルは公開面の再エクスポートだけを置く（クエリも定数も持たない）。
 * 外から使う名前はここに足し、モジュール間でしか使わない名前は足さない。
 *
 * 日付・時間帯のバケットはすべて JST 基準（lib/jst.ts が唯一の定義元）。
 * 期間の絞り込みは `WHERE timestamp >= ?` だけで行い、idx_events_timestamp /
 * idx_events_kind が効く形を保つ。
 */

export { type TrafficClass } from './access-class'
export { type KindBreakdown, type TrafficSplit, trafficSplit } from './breakdowns'
export { type DeliveryDailyPoint, type RouteSplit } from './delivery'
export {
  type EventCursor,
  type EventPage,
  type RecentEvent,
  eventPage,
  eventsAfter,
  maxEventId,
  parseEventCursor,
  recentEvents,
} from './events'
export {
  DOWNLOAD_METRICS,
  KIND_LABELS,
  METRIC_EXPR,
  OPERATIONAL_KINDS,
  OVERVIEW_METRICS,
  VERSION_BREAKDOWN_METRICS,
  type KindCounts,
  type MetricKey,
  metricOf,
  newDownloads,
  updateDownloads,
} from './metrics'
export {
  type EventBreakdowns,
  type RouteTotals,
  type Split,
  type VisitBreakdowns,
  eventBreakdowns,
} from './routes'
export {
  DAILY_WINDOW_DAYS,
  DASHBOARD_PAGES,
  DASHBOARD_PAGE_KEYS,
  DELIVERY_RECENT_DAYS,
  DELIVERY_WINDOW_DAYS,
  EVENTS_PAGE_LIMIT,
  STREAM_LIMIT,
  TOP_N,
  UNRECORDED_LABEL,
  type Count,
  type DashboardPage,
  type DashboardPageKey,
} from './shared'
export {
  RUNNING_VERSION_LABELS,
  RUNNING_VERSION_TABLE_LABELS,
  UNIQUE_SOURCE_LABELS,
  type RunningVersionKey,
  type RunningVersionTableKey,
  type RunningVersions,
  type UniqueSourceKey,
  type UniqueSources,
} from './sources'
export {
  type DeliverySummary,
  type OverviewSummary,
  type TrafficSummary,
  type UsersSummary,
  summarizeDelivery,
  summarizeOverview,
  summarizeTraffic,
  summarizeUsers,
} from './summaries'
export {
  type CumulativeTotals,
  type DailyPoint,
  type HourlyPoint,
  type TodayTotals,
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  todayTotals,
} from './totals'
export {
  type AdoptionCurve,
  type AdoptionPoint,
  type ConversionPoint,
  type UpdateConversion,
} from './users'
