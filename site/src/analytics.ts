/** ダッシュボード向けの集計。規模が小さいため都度 GROUP BY で算出する。 */

export type Count = { label: string; count: number }

export type RecentEvent = {
  id: number
  ts: number
  kind: string
  version: string | null
  country: string | null
  os: string | null
}

export type Totals = {
  visits: number
  downloads: number
  updateChecks: number
  uniqueVisitorDays: number
}

export type Summary = {
  totals: Totals
  dailyDownloads: Count[]
  byVersion: Count[]
  byCountry: Count[]
  byOS: Count[]
  byReferrer: Count[]
  byAsOrg: Count[]
  recent: RecentEvent[]
}

const DAILY_WINDOW_DAYS = 14
const TOP_N = 10
const RECENT_LIMIT = 20

/** 種別ごとの総数と、日次ユニークビジター（visitor_day の異なり数）。 */
export async function totals(db: D1Database): Promise<Totals> {
  const row = await db
    .prepare(
      `SELECT
         SUM(kind = 'visit')                AS visits,
         SUM(kind = 'download')             AS downloads,
         SUM(kind = 'update_check')         AS update_checks,
         COUNT(DISTINCT visitor_day)        AS unique_visitor_days
       FROM events`,
    )
    .first<{
      visits: number | null
      downloads: number | null
      update_checks: number | null
      unique_visitor_days: number | null
    }>()

  return {
    visits: row?.visits ?? 0,
    downloads: row?.downloads ?? 0,
    updateChecks: row?.update_checks ?? 0,
    uniqueVisitorDays: row?.unique_visitor_days ?? 0,
  }
}

/** 直近 14 日の日別ダウンロード数（UTC 日付）。 */
export async function dailyDownloads(db: D1Database, now: number): Promise<Count[]> {
  const since = now - DAILY_WINDOW_DAYS * 24 * 60 * 60 * 1000
  const { results } = await db
    .prepare(
      `SELECT date(ts / 1000, 'unixepoch') AS label, COUNT(*) AS count
       FROM events
       WHERE kind = 'download' AND ts >= ?
       GROUP BY label
       ORDER BY label`,
    )
    .bind(since)
    .all<Count>()

  return results
}

/** 内訳を取れるカラム。SQL へ差し込むため、外部入力を受けない固定の集合に限る。 */
type BreakdownColumn = 'version' | 'country' | 'os' | 'referrer' | 'as_org'

/** 指定カラムの内訳（上位 N 件、NULL は除外）。 */
async function breakdown(
  db: D1Database,
  column: BreakdownColumn,
  kind: string | null = null,
): Promise<Count[]> {
  const { results } = await db
    .prepare(
      `SELECT ${column} AS label, COUNT(*) AS count
       FROM events
       WHERE ${column} IS NOT NULL AND (?1 IS NULL OR kind = ?1)
       GROUP BY label
       ORDER BY count DESC, label
       LIMIT ${TOP_N}`,
    )
    .bind(kind)
    .all<Count>()

  return results
}

/** 最新イベント。SSE の差分取得と同じ形状で返す。 */
export async function recentEvents(db: D1Database, afterId = 0): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT id, ts, kind, version, country, os
       FROM events
       WHERE id > ?
       ORDER BY id DESC
       LIMIT ?`,
    )
    .bind(afterId, RECENT_LIMIT)
    .all<RecentEvent>()

  return results
}

/** ダッシュボード初期表示用の集計一式。 */
export async function summarize(db: D1Database, now: number): Promise<Summary> {
  const [aggregate, daily, byVersion, byCountry, byOS, byReferrer, byAsOrg, recent] =
    await Promise.all([
      totals(db),
      dailyDownloads(db, now),
      breakdown(db, 'version', 'download'),
      breakdown(db, 'country'),
      breakdown(db, 'os'),
      breakdown(db, 'referrer'),
      breakdown(db, 'as_org'),
      recentEvents(db),
    ])

  return {
    totals: aggregate,
    dailyDownloads: daily,
    byVersion,
    byCountry,
    byOS,
    byReferrer,
    byAsOrg,
    recent,
  }
}

/** SSE で push する新着イベント（古い順）。 */
export async function eventsAfter(db: D1Database, afterId: number): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT id, ts, kind, version, country, os
       FROM events
       WHERE id > ?
       ORDER BY id
       LIMIT 100`,
    )
    .bind(afterId)
    .all<RecentEvent>()

  return results
}

/** 現在の最大イベント ID（SSE の開始位置）。 */
export async function maxEventId(db: D1Database): Promise<number> {
  const row = await db.prepare('SELECT MAX(id) AS id FROM events').first<{ id: number | null }>()
  return row?.id ?? 0
}
