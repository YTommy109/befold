/**
 * 利用者面の集計（稼働バージョン分布・更新の転換率・取り込み曲線）。
 * 日別・時間帯別の件数は totals.ts にある。
 */

import { DAY_MS, JST_DAY_EXPR, jstDaysInWindow, jstWindowStart } from '../lib/jst'
import { HUMAN_ONLY } from './access-class'
import { METRIC_FILTERS, metricExpression } from './metrics'
import { type Count, DAILY_WINDOW_DAYS, TOP_N } from './shared'
import {
  RUNNING_VERSION_LABELS,
  RUNNING_VERSION_TABLE_LABELS,
  type RunningVersionKey,
  type RunningVersionTableKey,
  type RunningVersions,
} from './sources'

/**
 * 転換率の 1 日分（チャネル別）。
 *
 * `checked` が分母、`converted` が分子。分子は「同じ日・同じチャネルで確認と
 * sparkle 経由の更新の**両方**を持つアクセス元」で、単純な更新数ではない。
 * 更新側だけを分子にすると 100% を超えうる（実測: 本番 D1 に同日の確認記録が
 * 無い更新が存在する）。取りこぼしを率の中に隠さないため、その数を
 * `downloadedWithoutCheck` として別に持つ。
 *
 * 数える単位は visitor_token の異なり数（「アクセス元×日」）。visitor_token は
 * 生の User-Agent をハッシュ材料に含むので、appcast の取得と DMG の取得で UA が
 * 変われば同じ端末でも別のアクセス元として数える。
 */
export type ConversionPoint = {
  day: string
  checked: number
  converted: number
  downloadedWithoutCheck: number
}

/** チャネル別の転換率系列。0 件のチャネルも空配列で残す。 */
export type UpdateConversion = Record<RunningVersionKey, ConversionPoint[]>

/** 取り込み曲線の 1 点。`elapsedDays` は初回観測日からの経過日数。 */
export type AdoptionPoint = { elapsedDays: number; sources: number }

/**
 * タグ 1 つ分の取り込み曲線。
 *
 * `firstSeenDay` は**リリースの公開日ではなく、そのタグの sparkle 経由の
 * ダウンロードを最初に観測した日**。events にリリースの公開時刻は無く、
 * R2 の `latest.json` も `{version, file}` だけで日付を持たない。
 */
export type AdoptionCurve = {
  version: string
  channel: RunningVersionKey
  firstSeenDay: string
  cumulative: AdoptionPoint[]
}

/**
 * 直近 N 日に稼働していたバージョンの分布を、チャネル別に 1 本のクエリで取る。
 *
 * **数えるのは延べ確認回数ではなくアクセス元の異なり数。** `update_check` は
 * アプリが定期的に飛ばすため、件数はバージョンではなく起動回数に比例してしまう。
 * `visitor_token` は「接続元 IP と UA の組をその日のうちだけ同一視できるハッシュ」
 * なので、ここで数えているのは**アクセス元×日**の異なり数（`cumulativeTotals` の
 * `visitor_days` と同じ単位）。通算のユニーク利用者数ではない。
 *
 * **全期間ではなく直近 N 日に絞る。** 見たいのは「今どのバージョンが使われ続けて
 * いるか」であって、過去に一度でも動いた版の履歴ではない。全期間で数えると、
 * すでに更新を終えた版がいつまでも分布に残る。
 *
 * **チャネルを分ける。** 実測（2026-08-16）で `update_check` 132 件のうち develop が
 * 81 件と多数を占め、これは開発機からの確認。混ぜると stable 利用者の分布が読めない。
 *
 * 軸を行に持たせて上位 N 件を窓で切るのは `metricBreakdowns` と同じ形。
 */
export async function runningVersionBreakdown(
  db: D1Database,
  now: number,
): Promise<RunningVersions> {
  const { results } = await db
    .prepare(
      `WITH grouped AS (
         SELECT COALESCE(channel, 'unrecorded') AS channel, app_version AS label,
                COUNT(DISTINCT visitor_token) AS count
         FROM events
         WHERE app_version IS NOT NULL AND timestamp >= ?
               AND COALESCE(channel, 'unrecorded') <> 'develop'
               AND ${metricExpression(METRIC_FILTERS.update_check)} AND ${HUMAN_ONLY}
         GROUP BY channel, label
       ),
       ranked AS (
         SELECT channel, label, count,
                ROW_NUMBER() OVER (
                  PARTITION BY channel ORDER BY count DESC, label
                ) AS position
         FROM grouped
       )
       SELECT channel, label, count
       FROM ranked
       WHERE position <= ${TOP_N}
       ORDER BY channel, position`,
    )
    .bind(jstWindowStart(now, DAILY_WINDOW_DAYS))
    .all<Count & { channel: RunningVersionTableKey }>()

  // 0 件のチャネルも空配列で残す（表そのものを消さないため）。
  const byChannel = {} as RunningVersions
  for (const { key } of RUNNING_VERSION_TABLE_LABELS) byChannel[key] = []
  for (const { channel, label, count } of results) {
    byChannel[channel]?.push({ label, count })
  }

  return byChannel
}

/**
 * アップデートの取り込み（転換率とタグ別の取り込み曲線）を 1 本のクエリで取る。
 *
 * 2 つの指標はどちらも「アクセス元をいったん畳んでから数える」形で、行単位の
 * `CASE` を並べる日別推移のクエリには相乗りできない（同じアクセス元が確認の行と
 * 更新の行の両方を持つか、は行を見ただけでは分からない）。指標ごとに引かず
 * `UNION ALL` の 2 枝にして 1 本に収める（`metricBreakdowns` と同じ手）。
 *
 * どちらの枝も対象は直近 N 日。曲線のほうは「その窓の中で初めて観測されたタグ」に
 * 限られるため、窓より前に出たタグは出てこない（画面の注記でその旨を示す）。
 */
export async function updateAdoption(
  db: D1Database,
  now: number,
): Promise<{ conversion: UpdateConversion; adoption: AdoptionCurve[] }> {
  const windowStart = jstWindowStart(now, DAILY_WINDOW_DAYS)
  const isCheck = metricExpression(METRIC_FILTERS.update_check)
  const isUpdate = metricExpression(METRIC_FILTERS.update_download)

  const { results } = await db
    .prepare(
      `WITH sources AS (
         SELECT ${JST_DAY_EXPR} AS day,
                COALESCE(channel, 'unrecorded') AS channel,
                visitor_token,
                version,
                MAX(CASE WHEN ${isCheck} THEN 1 ELSE 0 END) AS checked,
                MAX(CASE WHEN ${isUpdate} THEN 1 ELSE 0 END) AS updated
         FROM events
         WHERE timestamp >= ? AND ${HUMAN_ONLY} AND ((${isCheck}) OR (${isUpdate}))
         GROUP BY day, channel, visitor_token, version
       ),
       per_source AS (
         SELECT day, channel, visitor_token,
                MAX(checked) AS checked,
                MAX(updated) AS updated
         FROM sources
         GROUP BY day, channel, visitor_token
       ),
       conversion AS (
         SELECT 'conversion' AS branch, day, channel, NULL AS version,
                SUM(checked) AS checked,
                SUM(CASE WHEN checked = 1 AND updated = 1 THEN 1 ELSE 0 END) AS converted,
                SUM(CASE WHEN checked = 0 AND updated = 1 THEN 1 ELSE 0 END) AS orphan
         FROM per_source
         GROUP BY day, channel
       ),
       adoption AS (
         SELECT 'adoption' AS branch, day, channel, version,
                COUNT(DISTINCT visitor_token) AS checked, 0 AS converted, 0 AS orphan
         FROM sources
         WHERE updated = 1 AND version IS NOT NULL
         GROUP BY day, channel, version
       )
       SELECT * FROM conversion
       UNION ALL
       SELECT * FROM adoption
       ORDER BY branch, day`,
    )
    .bind(windowStart)
    .all<{
      branch: 'adoption' | 'conversion'
      day: string
      channel: RunningVersionKey
      version: string | null
      checked: number
      converted: number
      orphan: number
    }>()

  // データの無い日も 0 で埋める（`dailySeries` と同じ扱い）。埋めないと、
  // 「その日は誰も確認しなかった」と「その日は数えていない」が区別できない。
  const byChannelDay = new Map<string, ConversionPoint>()
  const conversion = {} as UpdateConversion
  for (const { key } of RUNNING_VERSION_LABELS) {
    conversion[key] = jstDaysInWindow(now, DAILY_WINDOW_DAYS).map((day) => {
      const point = { day, checked: 0, converted: 0, downloadedWithoutCheck: 0 }
      byChannelDay.set(`${key}\t${day}`, point)
      return point
    })
  }

  // タグごとに「観測日 → その日のアクセス元数」を集めてから累積へ畳む。
  const perTag = new Map<string, { channel: RunningVersionKey; byDay: Map<string, number> }>()

  for (const row of results) {
    if (row.branch === 'conversion') {
      const point = byChannelDay.get(`${row.channel}\t${row.day}`)
      if (point !== undefined) {
        point.checked = row.checked
        point.converted = row.converted
        point.downloadedWithoutCheck = row.orphan
      }
      continue
    }

    if (row.version === null) continue
    const entry = perTag.get(row.version) ?? { channel: row.channel, byDay: new Map() }
    entry.byDay.set(row.day, (entry.byDay.get(row.day) ?? 0) + row.checked)
    perTag.set(row.version, entry)
  }

  const adoption = [...perTag.entries()]
    .map(([version, { channel, byDay }]) => {
      const days = [...byDay.keys()].toSorted()
      const firstSeenDay = days[0] ?? ''
      const start = Date.parse(`${firstSeenDay}T00:00:00Z`)
      let running = 0

      return {
        version,
        channel,
        firstSeenDay,
        cumulative: days.map((day) => {
          running += byDay.get(day) ?? 0
          return {
            elapsedDays: Math.round((Date.parse(`${day}T00:00:00Z`) - start) / DAY_MS),
            sources: running,
          }
        }),
      }
    })
    .toSorted((left, right) => right.firstSeenDay.localeCompare(left.firstSeenDay))

  return { conversion, adoption }
}
