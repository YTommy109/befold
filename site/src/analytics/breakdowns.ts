/**
 * 流入面の内訳クエリ（国・参照元・区分・指標 × 軸）。
 * 経路・言語の畳み込みは routes.ts、配信面の窓は delivery.ts に置く。
 */

import {
  HUMAN_ONLY,
  TRAFFIC_CLASSES,
  TRAFFIC_CLASS_EXPR,
  TRAFFIC_LABEL_EXPR,
  type TrafficClass,
} from './access-class'
import {
  KIND_LABELS,
  METRIC_EXPR,
  METRIC_FILTERS,
  type MetricKey,
  metricExpression,
} from './metrics'
import { type Count, TOP_N, UNRECORDED_LABEL } from './shared'

/** 1 指標（イベント種別）ごとの総数と内訳。合算せず指標別に見せるための単位。 */
export type KindBreakdown = {
  kind: MetricKey
  label: string
  total: number
  byOS: Count[]
  byAsOrg: Count[]
  /** バージョン別。version 列を持たない指標（visit など）では空になる。 */
  byVersion: Count[]
}

/** 内訳を取れるカラム。SQL へ差し込むため、外部入力を受けない固定の集合に限る。 */
type BreakdownColumn = 'version' | 'country' | 'os' | 'referrer' | 'as_org'

/** 指定カラムの内訳（上位 N 件、NULL は除外）。 */
export async function breakdown(db: D1Database, column: BreakdownColumn): Promise<Count[]> {
  const { results } = await db
    .prepare(
      `SELECT ${column} AS label, COUNT(*) AS count
       FROM events
       WHERE ${column} IS NOT NULL
         AND ${HUMAN_ONLY}
       GROUP BY label
       ORDER BY count DESC, label
       LIMIT ${TOP_N}`,
    )
    .all<Count>()

  return results
}

/** `referrerBreakdowns` が 1 本のクエリで返す 2 つの母集団。 */
export type ReferrerScope = 'all' | 'download'

/**
 * 参照元の内訳を 2 つの母集団ぶん、**1 クエリ**で取る。
 *
 * - `all`: 全イベント。「どこから来訪したか」を見る従来の軸（挙動は変えない）
 * - `download`: 新規獲得のダウンロード（`METRIC_FILTERS.download`）だけ。
 *   `?ref=` が「ダウンロードが始まった面」を運ぶようになったため（TASK-549）、
 *   全体とは別の問いに答える
 *
 * 2 本のクエリに分けないのは、流入面のクエリ本数が上限ちょうど（`MAX_QUERIES_PER_PAGE`）
 * だから。`docs/dev/development.md` が「指標を足すときは既存クエリへ列を足すか
 * UNION ALL で束ねる」と定めており、区分を行に持たせて `ROW_NUMBER` の窓で上位 N を
 * 切る形は `trafficSplit` と同じ。
 *
 * `download` 側だけ `COALESCE(referrer, UNRECORDED_LABEL)` にする。ref を持たない
 * ダウンロード（外部からの直リンク・ブックマーク）が `IS NOT NULL` で行ごと消えると、
 * 「LP 経由しか無い」と読み違えるため——消さずに未記録として並べる。
 */
export async function referrerBreakdowns(db: D1Database): Promise<Record<ReferrerScope, Count[]>> {
  const downloadFilter = metricExpression(METRIC_FILTERS.download)
  const { results } = await db
    .prepare(
      `WITH scoped AS (
         SELECT '${'all' satisfies ReferrerScope}' AS scope, referrer AS label
         FROM events
         WHERE referrer IS NOT NULL AND ${HUMAN_ONLY}
         UNION ALL
         SELECT '${'download' satisfies ReferrerScope}' AS scope,
                COALESCE(referrer, '${UNRECORDED_LABEL}') AS label
         FROM events
         WHERE ${HUMAN_ONLY} AND ${downloadFilter}
       ),
       counted AS (
         SELECT scope, label, COUNT(*) AS count FROM scoped GROUP BY scope, label
       ),
       ranked AS (
         SELECT scope, label, count,
                ROW_NUMBER() OVER (PARTITION BY scope ORDER BY count DESC, label) AS rank
         FROM counted
       )
       SELECT scope, label, count FROM ranked WHERE rank <= ${TOP_N}
       ORDER BY scope, count DESC, label`,
    )
    .all<Count & { scope: ReferrerScope }>()

  return {
    all: results.filter((row) => row.scope === 'all').map(({ label, count }) => ({ label, count })),
    download: results
      .filter((row) => row.scope === 'download')
      .map(({ label, count }) => ({ label, count })),
  }
}

/**
 * 区分ごとの総数と内訳（全期間の累計）。
 *
 * `totals` は総数、`breakdowns` は上位 N 件の内訳。総数を内訳の合計から出さないのは、
 * 内訳が上位 N 件で切られており、種類が多いほど実際より小さく見えるため。
 *
 * 内訳のラベルは区分で意味が変わる。`human` / `bot` は `ua_summary`（クライアント
 * 種別・クローラ名）、`datacenter` は `as_org`（接続元組織）。データセンター側で
 * UA を出しても `Chrome` や `other` が並ぶだけで、どこから来たのかが読めない。
 */
export type TrafficSplit = {
  totals: Record<TrafficClass, number>
  breakdowns: Record<TrafficClass, Count[]>
}

/**
 * 区分ごとの総数と内訳を 2 本のクエリで取る。
 *
 * 区分ごとに引かない（3 区分 × 内訳で全表スキャンが並ぶ）。内訳は区分を行に
 * 持たせて 1 本にまとめ、上位 N 件の切り出しは `ROW_NUMBER()` の窓で区分ごとに
 * 行う（`metricBreakdown` と同じ形）。`query-count.test.ts` の上限がこの形を守る。
 */
export async function trafficSplit(db: D1Database): Promise<TrafficSplit> {
  const [totalRows, breakdownRows] = await Promise.all([
    db
      .prepare(
        `SELECT ${TRAFFIC_CLASS_EXPR} AS class, COUNT(*) AS count
         FROM events
         GROUP BY class`,
      )
      .all<{ class: TrafficClass; count: number }>(),
    db
      .prepare(
        `WITH grouped AS (
           SELECT ${TRAFFIC_CLASS_EXPR} AS class, ${TRAFFIC_LABEL_EXPR} AS label,
                  COUNT(*) AS count
           FROM events
           GROUP BY class, label
         ),
         ranked AS (
           SELECT class, label, count,
                  ROW_NUMBER() OVER (PARTITION BY class ORDER BY count DESC, label) AS position
           FROM grouped
         )
         SELECT class, label, count
         FROM ranked
         WHERE position <= ${TOP_N}
         ORDER BY class, position`,
      )
      .all<Count & { class: TrafficClass }>(),
  ])

  const totals = {} as Record<TrafficClass, number>
  const breakdowns = {} as Record<TrafficClass, Count[]>
  for (const trafficClass of TRAFFIC_CLASSES) {
    totals[trafficClass] = 0
    breakdowns[trafficClass] = []
  }
  for (const row of totalRows.results) totals[row.class] = row.count
  for (const { class: trafficClass, label, count } of breakdownRows.results) {
    breakdowns[trafficClass].push({ label, count })
  }

  return { totals, breakdowns }
}

/**
 * 指標別の内訳を取る軸。SQL へ差し込むため、外部入力を受けない固定の集合に限る。
 *
 * 軸を増やしてもクエリは 1 本のまま（`metricBreakdowns` が `UNION ALL` で
 * 軸を行に持たせる）。軸ごとに 1 本ずつ引く形へ戻すと `query-count.test.ts` の
 * 上限で落ちる。
 */
const METRIC_BREAKDOWN_AXES = ['os', 'as_org', 'version'] as const

type MetricBreakdownAxis = (typeof METRIC_BREAKDOWN_AXES)[number]

/**
 * 全指標・全軸ぶんの内訳を 1 本のクエリで取る（指標ごと・軸ごとに上位 N 件）。
 *
 * 指標ごとに引くと `(?1 IS NULL OR kind = ?1)` の形の述語で全表スキャンが指標の数
 * だけ並ぶ。指標を行に持たせて 1 本にまとめ、上位 N 件の切り出しは
 * `ROW_NUMBER()` の窓で指標ごとに行う（LIMIT だと 1 指標ぶんしか取れない）。
 *
 * 軸（os / as_org / version）も同じ理由で行に持たせる。`trafficSplit` の区分・
 * `eventBreakdowns` の列と同じ「増やす方向を行にして窓で切る」形で、軸を足しても
 * 発行本数は増えない。
 */
async function metricBreakdowns(
  db: D1Database,
): Promise<Map<MetricBreakdownAxis, Map<MetricKey, Count[]>>> {
  const branches = METRIC_BREAKDOWN_AXES.map(
    (axis) =>
      `SELECT '${axis}' AS axis, ${METRIC_EXPR} AS metric, ${axis} AS label, COUNT(*) AS count
         FROM events
         WHERE ${axis} IS NOT NULL AND ${HUMAN_ONLY}
         GROUP BY metric, label`,
  ).join(' UNION ALL ')

  const { results } = await db
    .prepare(
      `WITH grouped AS (${branches}),
       ranked AS (
         SELECT axis, metric, label, count,
                ROW_NUMBER() OVER (
                  PARTITION BY axis, metric ORDER BY count DESC, label
                ) AS position
         FROM grouped
         WHERE metric IS NOT NULL
       )
       SELECT axis, metric, label, count
       FROM ranked
       WHERE position <= ${TOP_N}
       ORDER BY axis, metric, position`,
    )
    .all<Count & { axis: MetricBreakdownAxis; metric: MetricKey }>()

  const byAxis = new Map<MetricBreakdownAxis, Map<MetricKey, Count[]>>()
  for (const axis of METRIC_BREAKDOWN_AXES) byAxis.set(axis, new Map())
  for (const { axis, metric, label, count } of results) {
    const byMetric = byAxis.get(axis)
    if (byMetric === undefined) continue
    const counts = byMetric.get(metric) ?? []
    counts.push({ label, count })
    byMetric.set(metric, counts)
  }

  return byAxis
}

/** 指標ごとの OS 別・接続元組織別・バージョン別の内訳。合算しないため指標の意味が混ざらない。 */
export async function kindBreakdowns(db: D1Database): Promise<Omit<KindBreakdown, 'total'>[]> {
  const byAxis = await metricBreakdowns(db)
  const byOS = byAxis.get('os') ?? new Map<MetricKey, Count[]>()
  const byAsOrg = byAxis.get('as_org') ?? new Map<MetricKey, Count[]>()
  const byVersion = byAxis.get('version') ?? new Map<MetricKey, Count[]>()

  return KIND_LABELS.map(({ kind, label }) => ({
    kind,
    label,
    byOS: byOS.get(kind) ?? [],
    byAsOrg: byAsOrg.get(kind) ?? [],
    byVersion: byVersion.get(kind) ?? [],
  }))
}
