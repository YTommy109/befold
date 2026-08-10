/**
 * ダッシュボード向けの集計。規模が小さいため都度 GROUP BY で算出する。
 *
 * 日付・時間帯のバケットはすべて JST 基準（lib/jst.ts が唯一の定義元）。
 * 期間の絞り込みは `WHERE timestamp >= ?` だけで行い、idx_events_timestamp /
 * idx_events_kind が効く形を保つ。
 */

import type { DownloadSource, EventKind } from './schema'
import { JST_DAY_EXPR, JST_HOUR_EXPR, jstDayStart, jstDaysInWindow, jstWindowStart } from './lib/jst'
import { BOT_PREFIX } from './lib/visitor'

export type Count = { label: string; count: number }

export type RecentEvent = {
  id: number
  timestamp: number
  kind: string
  version: string | null
  country: string | null
  os: string | null
}

/**
 * ダッシュボードで並べる指標。イベント種別と 1 対 1 ではない。
 *
 * `download` は配布 LP 経由の新規ダウンロード、`update_download` は Sparkle の
 * 自動アップデートによるダウンロード。どちらも events では kind='download' だが、
 * 前者は新規獲得、後者は既存ユーザの更新であり、混ぜると LP のダウンロード数が
 * 意味を失う。成果物を R2 へ移して enclosure が Worker を通るようになった
 * TASK-355 以降、後者が記録され始めた。
 */
export type MetricKey = EventKind | 'update_download'

/**
 * 指標を events の行へ落とすための述語。
 *
 * `source` が NULL の行は source 列の導入前に記録されたもので、当時 Worker を
 * 通るダウンロードは LP 経由しか存在しなかった。`COALESCE(source, 'lp')` は
 * その事実を表しており、過去データを含めた `download` 系列の意味を保つ。
 */
type MetricFilter = { kind: EventKind; source: DownloadSource | null }

const METRIC_FILTERS: Record<MetricKey, MetricFilter> = {
  visit: { kind: 'visit', source: null },
  download: { kind: 'download', source: 'lp' },
  update_download: { kind: 'download', source: 'sparkle' },
  update_check: { kind: 'update_check', source: null },
}

/** 指標ごとの件数。 */
export type KindCounts = Record<MetricKey, number>

/**
 * 全期間の累計。
 *
 * `visitorDays` は visitor_token の異なり数、すなわち「訪問者 × 日」の延べ数で
 * あって、ユニーク訪問者数ではない（visitor_token は日ごとに別ハッシュになる）。
 * 当日集計の `uniqueVisitors` と名前を分けているのは、同じ SQL 断片が期間次第で
 * 別の意味になり、混用しても値が返ってしまうため。
 */
export type CumulativeTotals = { counts: KindCounts; visitorDays: number }

/** JST 当日（0 時以降）の集計。`uniqueVisitors` は当日のユニーク訪問者数。 */
export type TodayTotals = { counts: KindCounts; uniqueVisitors: number }

/** 日別推移の 1 点。データが無い日も 0 で埋めて返す。 */
export type DailyPoint = { day: string; counts: KindCounts; uniqueVisitors: number }

/** 時間帯分布の 1 点。0〜23 時が必ずそろう。 */
export type HourlyPoint = { hour: number; counts: KindCounts }

/** 1 指標（イベント種別）ごとの総数と内訳。合算せず指標別に見せるための単位。 */
export type KindBreakdown = {
  kind: MetricKey
  label: string
  total: number
  byOS: Count[]
  byAsOrg: Count[]
}

export type Summary = {
  windowDays: number
  cumulative: CumulativeTotals
  today: TodayTotals
  daily: DailyPoint[]
  hourly: HourlyPoint[]
  byVersion: Count[]
  byCountry: Count[]
  byReferrer: Count[]
  ua: UASplit
  perKind: KindBreakdown[]
  recent: RecentEvent[]
}

/** 指標として並べる順序と表示名。ページ表示・集計の双方でこの順を使う。 */
const KIND_LABELS: { kind: MetricKey; label: string }[] = [
  { kind: 'visit', label: 'ページアクセス' },
  { kind: 'download', label: 'ダウンロード' },
  { kind: 'update_check', label: 'アップデート確認' },
  { kind: 'update_download', label: '自動アップデート適用' },
]

/** 日別推移・時間帯分布が対象にする窓（当日を含む直近 N 日）。 */
export const DAILY_WINDOW_DAYS = 14
const TOP_N = 10
const RECENT_LIMIT = 20

/** SSE の 1 周期で流す新着イベントの上限。再開位置の判断に呼び出し側も使う。 */
export const STREAM_LIMIT = 100

/**
 * ボット判定の SQL 側の表現。値の列挙は持たず接頭辞だけで分ける（lib/visitor.ts）。
 *
 * `COALESCE` を外さないこと。`ua_summary` は NULL 許容で、`NULL LIKE ...` は
 * NULL を返す。素の LIKE を WHERE に置くと、UA ヘッダの無いリクエストで
 * 記録された行が人間でもボットでもなく黙って全集計から消える。
 */
const BOT_MATCH = `COALESCE(ua_summary, '') LIKE '${BOT_PREFIX}%'`

/**
 * ロボットの巡回を集計から外すための条件。集計クエリはこれを WHERE へ足す。
 *
 * ボット除外の条件はこの 1 箇所だけに置く（集計ごとに書き写さない）。この規約は
 * `analytics.test.ts` の「FROM events を含むクエリは HUMAN_ONLY を含むか、
 * 意図的な除外リストに載っているか」を検査するテストが担保する。
 *
 * 分類（TASK-386）の適用前に記録された行は種類が分からず 'other' または NULL に
 * 丸まっており、ここでは人間側に残る。遡って分類し直す材料（完全な UA）を
 * 保存していないため。この非連続性はダッシュボードの注記で示す。
 */
const HUMAN_ONLY = `NOT ${BOT_MATCH}`

/** 種別ごとの件数を 1 行から取り出すための SELECT 句。 */
const KIND_COUNT_COLUMNS =
  `SUM(kind = 'visit')        AS visits,
   SUM(kind = 'download' AND COALESCE(source, 'lp') = 'lp')      AS downloads,
   SUM(kind = 'download' AND COALESCE(source, 'lp') = 'sparkle') AS update_downloads,
   SUM(kind = 'update_check') AS update_checks`

type KindCountRow = {
  visits: number | null
  downloads: number | null
  update_downloads: number | null
  update_checks: number | null
}

function toKindCounts(row: KindCountRow | null): KindCounts {
  return {
    visit: row?.visits ?? 0,
    download: row?.downloads ?? 0,
    update_download: row?.update_downloads ?? 0,
    update_check: row?.update_checks ?? 0,
  }
}

/** 全期間の累計（種別ごとの件数と、訪問者 × 日の延べ数）。 */
export async function cumulativeTotals(db: D1Database): Promise<CumulativeTotals> {
  const row = await db
    .prepare(
      `SELECT ${KIND_COUNT_COLUMNS},
              COUNT(DISTINCT visitor_token) AS visitor_days
       FROM events
       WHERE ${HUMAN_ONLY}`,
    )
    .first<KindCountRow & { visitor_days: number | null }>()

  return { counts: toKindCounts(row), visitorDays: row?.visitor_days ?? 0 }
}

/** JST 当日ぶんの集計。全期間の延べ数ではなく、当日のみを数える。 */
export async function todayTotals(db: D1Database, now: number): Promise<TodayTotals> {
  const row = await db
    .prepare(
      `SELECT ${KIND_COUNT_COLUMNS},
              COUNT(DISTINCT visitor_token) AS unique_visitors
       FROM events
       WHERE timestamp >= ? AND ${HUMAN_ONLY}`,
    )
    .bind(jstDayStart(now))
    .first<KindCountRow & { unique_visitors: number | null }>()

  return { counts: toKindCounts(row), uniqueVisitors: row?.unique_visitors ?? 0 }
}

/** 当日を含む直近 N 日の日別推移（JST 日バケット、データが無い日は 0）。 */
export async function dailySeries(
  db: D1Database,
  now: number,
  days = DAILY_WINDOW_DAYS,
): Promise<DailyPoint[]> {
  const { results } = await db
    .prepare(
      `SELECT ${JST_DAY_EXPR} AS day,
              ${KIND_COUNT_COLUMNS},
              COUNT(DISTINCT visitor_token) AS unique_visitors
       FROM events
       WHERE timestamp >= ? AND ${HUMAN_ONLY}
       GROUP BY day
       ORDER BY day`,
    )
    .bind(jstWindowStart(now, days))
    .all<KindCountRow & { day: string; unique_visitors: number | null }>()

  const byDay = new Map(results.map((row) => [row.day, row]))

  return jstDaysInWindow(now, days).map((day) => {
    const row = byDay.get(day) ?? null
    return { day, counts: toKindCounts(row), uniqueVisitors: row?.unique_visitors ?? 0 }
  })
}

/** 当日を含む直近 N 日の時間帯分布（JST 時バケット、0〜23 時が必ずそろう）。 */
export async function hourlyDistribution(
  db: D1Database,
  now: number,
  days = DAILY_WINDOW_DAYS,
): Promise<HourlyPoint[]> {
  const { results } = await db
    .prepare(
      `SELECT CAST(${JST_HOUR_EXPR} AS INTEGER) AS hour,
              ${KIND_COUNT_COLUMNS}
       FROM events
       WHERE timestamp >= ? AND ${HUMAN_ONLY}
       GROUP BY hour
       ORDER BY hour`,
    )
    .bind(jstWindowStart(now, days))
    .all<KindCountRow & { hour: number }>()

  const byHour = new Map(results.map((row) => [row.hour, row]))

  return Array.from({ length: 24 }, (_, hour) => ({
    hour,
    counts: toKindCounts(byHour.get(hour) ?? null),
  }))
}

/** 内訳を取れるカラム。SQL へ差し込むため、外部入力を受けない固定の集合に限る。 */
type BreakdownColumn = 'version' | 'country' | 'os' | 'referrer' | 'as_org'

/** 指定カラムの内訳（上位 N 件、NULL は除外）。 */
async function breakdown(
  db: D1Database,
  column: BreakdownColumn,
  metric: MetricKey | null = null,
): Promise<Count[]> {
  const filter = metric === null ? null : METRIC_FILTERS[metric]

  const { results } = await db
    .prepare(
      `SELECT ${column} AS label, COUNT(*) AS count
       FROM events
       WHERE ${column} IS NOT NULL
         AND ${HUMAN_ONLY}
         AND (?1 IS NULL OR kind = ?1)
         AND (?2 IS NULL OR COALESCE(source, 'lp') = ?2)
       GROUP BY label
       ORDER BY count DESC, label
       LIMIT ${TOP_N}`,
    )
    .bind(filter?.kind ?? null, filter?.source ?? null)
    .all<Count>()

  return results
}

/**
 * 人間の訪問とロボットの巡回の分離（全期間の累計）。
 *
 * `human` / `bot` は総数、`byHuman` / `byBot` は上位 N 件の内訳。総数を内訳の
 * 合計から出さないのは、内訳が上位 N 件で切られており、種類が多いほど実際より
 * 小さく見えるため。
 */
export type UASplit = { human: number; bot: number; byHuman: Count[]; byBot: Count[] }

/** ua_summary をボットかどうかで分けた総数と内訳。 */
export async function uaSplit(db: D1Database): Promise<UASplit> {
  const [totals, byHuman, byBot] = await Promise.all([
    db
      .prepare(
        `SELECT SUM(${BOT_MATCH})     AS bots,
                SUM(NOT ${BOT_MATCH}) AS humans
         FROM events
         WHERE ua_summary IS NOT NULL`,
      )
      .first<{ bots: number | null; humans: number | null }>(),
    uaBreakdown(db, false),
    uaBreakdown(db, true),
  ])

  return {
    human: totals?.humans ?? 0,
    bot: totals?.bots ?? 0,
    byHuman,
    byBot,
  }
}

/** ボット／人間のどちらかに絞った ua_summary の内訳（上位 N 件）。 */
async function uaBreakdown(db: D1Database, bots: boolean): Promise<Count[]> {
  const { results } = await db
    .prepare(
      `SELECT ua_summary AS label, COUNT(*) AS count
       FROM events
       WHERE ua_summary IS NOT NULL
         AND ${bots ? '' : 'NOT '}${BOT_MATCH}
       GROUP BY label
       ORDER BY count DESC, label
       LIMIT ${TOP_N}`,
    )
    .all<Count>()

  return results
}

/** 最新イベント。SSE の差分取得と同じ形状・同じ絞り込み（人間のみ）で返す。 */
export async function recentEvents(db: D1Database, afterId = 0): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT id, timestamp, kind, version, country, os
       FROM events
       WHERE id > ? AND ${HUMAN_ONLY}
       ORDER BY id DESC
       LIMIT ?`,
    )
    .bind(afterId, RECENT_LIMIT)
    .all<RecentEvent>()

  return results
}

/** 1 指標の OS 別・接続元組織別の内訳。合算しないため指標の意味が混ざらない。 */
async function kindBreakdown(
  db: D1Database,
  { kind, label }: { kind: MetricKey; label: string },
): Promise<Omit<KindBreakdown, 'total'>> {
  const [byOS, byAsOrg] = await Promise.all([
    breakdown(db, 'os', kind),
    breakdown(db, 'as_org', kind),
  ])

  return { kind, label, byOS, byAsOrg }
}

/** ダッシュボード初期表示用の集計一式。 */
export async function summarize(db: D1Database, now: number): Promise<Summary> {
  const [cumulative, today, daily, hourly, byVersion, byCountry, byReferrer, ua, breakdowns, recent] =
    await Promise.all([
      cumulativeTotals(db),
      todayTotals(db, now),
      dailySeries(db, now),
      hourlyDistribution(db, now),
      breakdown(db, 'version', 'download'),
      breakdown(db, 'country'),
      breakdown(db, 'referrer'),
      // ua_summary の内訳は AI クローラ（GPTBot / ClaudeBot 等）の到来量を
      // 実測するために持つ。TASK-360 で見送った llms.txt の要否判断に使う。
      uaSplit(db),
      Promise.all(KIND_LABELS.map((entry) => kindBreakdown(db, entry))),
      recentEvents(db),
    ])

  return {
    windowDays: DAILY_WINDOW_DAYS,
    cumulative,
    today,
    daily,
    hourly,
    byVersion,
    byCountry,
    byReferrer,
    ua,
    perKind: breakdowns.map((entry) => ({ ...entry, total: cumulative.counts[entry.kind] })),
    recent,
  }
}

/**
 * SSE で push する新着イベント（古い順、人間のみ）。
 *
 * 返らなかったボットの行のぶんカーソルが進まないため、呼び出し側はこの戻り値で
 * 再開位置を決めない（`maxEventId` で進める）。上限まで返った周期だけは、
 * まだ読んでいない行が残るので最後の id で止める必要がある。
 */
export async function eventsAfter(db: D1Database, afterId: number): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT id, timestamp, kind, version, country, os
       FROM events
       WHERE id > ? AND ${HUMAN_ONLY}
       ORDER BY id
       LIMIT ${STREAM_LIMIT}`,
    )
    .bind(afterId)
    .all<RecentEvent>()

  return results
}

/**
 * 現在の最大イベント ID（SSE の開始位置・再開位置）。
 *
 * ボットを含む生の id を返す。集計・表示はボットを除くが、カーソルまで除くと
 * ボットだけが到来した周期で位置が進まず、集計の再描画も起きなくなる。
 */
export async function maxEventId(db: D1Database): Promise<number> {
  const row = await db.prepare('SELECT MAX(id) AS id FROM events').first<{ id: number | null }>()
  return row?.id ?? 0
}
