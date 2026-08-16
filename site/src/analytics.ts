/**
 * ダッシュボード向けの集計。規模が小さいため都度 GROUP BY で算出する。
 *
 * 日付・時間帯のバケットはすべて JST 基準（lib/jst.ts が唯一の定義元）。
 * 期間の絞り込みは `WHERE timestamp >= ?` だけで行い、idx_events_timestamp /
 * idx_events_kind が効く形を保つ。
 */

import type { DownloadSource, EventKind, Page } from './schema'
import { RECORDED_HOSTS } from './lib/hosts'
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
  /** kind='visit' のときの訪問先ページ。それ以外の kind と、列の導入前の行では null。 */
  page: string | null
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
type MetricFilter = { kind: EventKind; source: DownloadSource | null; page: Page | null }

const METRIC_FILTERS: Record<MetricKey, MetricFilter> = {
  // 「ページアクセス」は LP への訪問だけを数える。TASK-488.1 で /features も
  // visit として記録し始めたが、この系列は LP からの新規獲得を測るものなので
  // 意味と過去データの連続性を保つために page で絞る。ページ別の内訳は別系列。
  visit: { kind: 'visit', source: null, page: '/' },
  download: { kind: 'download', source: 'lp', page: null },
  update_download: { kind: 'download', source: 'sparkle', page: null },
  update_check: { kind: 'update_check', source: null, page: null },
  // 下の 2 つは製品の指標ではなく運用の観測。`MetricKey` が `EventKind` を覆う
  // ため型としてここに現れるが、カード・グラフ（`KIND_LABELS`）には出さない。
  github_fallback: { kind: 'github_fallback', source: null, page: null },
  legacy_redirect: { kind: 'legacy_redirect', source: null, page: null },
}

/**
 * カード・グラフに並べない kind。運用の観測として専用セクションで見るもの。
 *
 * `KIND_LABELS` から漏れた kind が黙って画面のどこにも出ないことを防ぐための
 * 明示。両者を合わせて全 `MetricKey` を覆うことは `analytics.test.ts` が検査する
 * （kind を足したら、指標にするか運用観測にするかをここで必ず決めることになる）。
 */
export const OPERATIONAL_KINDS: ReadonlySet<MetricKey> = new Set<MetricKey>([
  'github_fallback',
  'legacy_redirect',
])

/**
 * 指標 1 つを SQL の条件式にする。**指標の述語はここだけで組み立てる。**
 *
 * `METRIC_EXPR`（内訳）・`metricCondition`（WHERE）・`KIND_COUNT_COLUMNS`（件数）の
 * 3 者が同じ述語を必要とする。かつては件数側だけが手書きで、page 列を足したときに
 * そこだけ同期漏れを起こす形だった。埋め込む値は `METRIC_FILTERS` の定数だけで、
 * 外部入力は入らない。
 *
 * `COALESCE(page, '/')` は `kind = 'visit'` と同じ式の中にしか現れない。page が
 * NULL の行には「列の導入前の visit（当時は LP のみ）」と「ページの概念が無い
 * download / update_check」の 2 種類があり、後者に '/' を与えると嘘になるため
 * （schema/schema.sql の page 列コメント）。この構造なら kind を伴わずに page 条件
 * だけを書く形にはならない。
 */
function metricExpression({ kind, source, page }: MetricFilter): string {
  const bySource = source === null ? '' : ` AND COALESCE(source, 'lp') = '${source}'`
  const byPage = page === null ? '' : ` AND COALESCE(page, '/') = '${page}'`
  return `kind = '${kind}'${bySource}${byPage}`
}

/**
 * 指標を SQL 側で判定する式（どの指標にも当たらない行は NULL）。
 *
 * 内訳を指標ごとに 1 本ずつ引くと指標の数だけ全表スキャンが増えるため、指標を行に
 * 持たせて 1 本にまとめるための式。埋め込む値は `METRIC_FILTERS` の定数だけで、
 * 外部入力は入らない。判定の定義元を二重に持たないよう、条件はここで組み立てる。
 */
const METRIC_EXPR = `CASE ${Object.entries(METRIC_FILTERS)
  .map(([metric, filter]) => `WHEN ${metricExpression(filter)} THEN '${metric}'`)
  .join(' ')} END`

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
  visits: VisitBreakdowns
  hosts: Split[]
  fallbacks: Split[]
  perKind: KindBreakdown[]
  recent: RecentEvent[]
}

/** 指標として並べる順序と表示名。ページ表示・集計の双方でこの順を使う。 */
export const KIND_LABELS: { kind: MetricKey; label: string }[] = [
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

/**
 * 種別ごとの件数を 1 行から取り出すための SELECT 句。
 *
 * 述語は書き写さず `metricExpression` から組み立てる。列名は指標キーそのものを
 * 使い、`toKindCounts` の対応表も指標キーから作る（片方だけ増えると型で落ちる）。
 */
const KIND_COUNT_COLUMNS = metricKeys()
  .map((metric) => `SUM(${metricExpression(METRIC_FILTERS[metric])}) AS ${metric}`)
  .join(', ')

type KindCountRow = Partial<Record<MetricKey, number | null>>

function metricKeys(): MetricKey[] {
  return Object.keys(METRIC_FILTERS) as MetricKey[]
}

function toKindCounts(row: KindCountRow | null): KindCounts {
  const counts = {} as KindCounts
  for (const metric of metricKeys()) counts[metric] = row?.[metric] ?? 0
  return counts
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

/**
 * 指標を WHERE 句へ落とす（指標を指定しなければ空）。
 *
 * `(? IS NULL OR kind = ?)` の形で無条件を表さないこと。この形は kind が定数に
 * ならず idx_events_kind が効かなくなるため、条件そのものを組み立てて外す。
 * 埋め込む値は `METRIC_FILTERS` の定数だけで、外部入力は入らない。
 */
function metricCondition(metric: MetricKey | null): string {
  if (metric === null) return ''

  return ` AND ${metricExpression(METRIC_FILTERS[metric])}`
}

/** 指定カラムの内訳（上位 N 件、NULL は除外）。 */
async function breakdown(
  db: D1Database,
  column: BreakdownColumn,
  metric: MetricKey | null = null,
): Promise<Count[]> {
  const { results } = await db
    .prepare(
      `SELECT ${column} AS label, COUNT(*) AS count
       FROM events
       WHERE ${column} IS NOT NULL
         AND ${HUMAN_ONLY}${metricCondition(metric)}
       GROUP BY label
       ORDER BY count DESC, label
       LIMIT ${TOP_N}`,
    )
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

/** 1 つの区分の、人間とロボットそれぞれの件数。 */
export type Split = { label: string; human: number; bot: number }

/**
 * visit の内訳（ページ別・表示言語別・ブラウザ言語設定別）。
 *
 * 3 つとも「visit を何かの軸で割った」ものなので、軸ごとにクエリを引かず
 * 1 本にまとめる（`eventBreakdowns`）。
 */
export type VisitBreakdowns = {
  byPage: Split[]
  byDisplayLang: Split[]
  byBrowserLang: Split[]
}

/** 1 本のクエリから畳んで作る内訳の一式。 */
export type EventBreakdowns = {
  visits: VisitBreakdowns
  /** リクエスト先ホスト別（全 kind）。0 件の既知ホストも行として残す。 */
  byHost: Split[]
  /** GitHub へ落ちた経路別（kind='github_fallback' のみ）。 */
  byFallback: Split[]
}

/** 値が記録されていない行のラベル。列の導入前に記録された visit がここに入る。 */
export const UNRECORDED_LABEL = '未記録'

/**
 * 内訳を 1 本のクエリで取り、軸ごとに TS 側で畳む。
 *
 * **クエリは 1 本。** 軸ごとに引くと全表スキャンが軸の数だけ並ぶ。値が列挙で
 * 抑えられた列の組で集約すれば、返る行は組み合わせの数（実際には kind ごとに
 * 埋まる列が違うので高々数十行）にしかならず、軸ごとの集計は TS 側で畳める。
 * この形を崩して軸ごとに引くと `query-count.test.ts` の上限で落ちる。
 *
 * `COALESCE(page, '/')` を SQL 側に置かないこと。page が NULL の行には「列の
 * 導入前に記録された visit（当時は LP だけなので '/' と読んでよい）」と
 * 「ページの概念が無い download / update_check / 運用イベント」の 2 種類があり、
 * 後者に '/' を与えると嘘になる（`schema/schema.sql` の page 列コメント）。
 * このクエリは kind を絞らないため、丸めは `kind = 'visit'` の行だけを対象に
 * TS 側（`visitRows`）で行う。
 *
 * ボット判定は `BOT_MATCH` をそのまま使う。ここで新しい判定を書かない——
 * 判定の定義元が増えると、`BOT_TOKENS` を足したときに片方だけ直る。
 */
export async function eventBreakdowns(db: D1Database): Promise<EventBreakdowns> {
  const { results } = await db
    .prepare(
      `SELECT kind, page, display_lang, browser_lang, host, fallback,
              COUNT(*) AS count, ${BOT_MATCH} AS is_bot
       FROM events
       GROUP BY kind, page, display_lang, browser_lang, host, fallback, is_bot`,
    )
    .all<BreakdownRow>()

  const visitRows = results.filter((row) => row.kind === 'visit')

  return {
    visits: {
      byPage: foldSplits(visitRows, (row) => row.page ?? '/'),
      byDisplayLang: foldSplits(visitRows, (row) => row.display_lang ?? UNRECORDED_LABEL),
      byBrowserLang: foldSplits(visitRows, (row) => row.browser_lang ?? UNRECORDED_LABEL),
    },
    byHost: foldHosts(results),
    byFallback: foldSplits(
      results.filter((row) => row.fallback !== null),
      (row) => row.fallback ?? UNRECORDED_LABEL,
    ),
  }
}

/** `eventBreakdowns` が受け取る 1 行。列の値はいずれも列挙か NULL に限る。 */
type BreakdownRow = {
  kind: string
  page: string | null
  display_lang: string | null
  browser_lang: string | null
  host: string | null
  fallback: string | null
  is_bot: number
  count: number
}

/**
 * ホスト別を畳む。**0 件の既知ホストも行として残す。**
 *
 * 件数のある区分だけを返すと、「旧ホストへのアクセスがまだ 0 だった」と
 * 「そもそも計測していない」が画面上で区別できなくなる。ADR 0007 の停止条件は
 * ゼロであることの確認そのものなので、0 を消してはならない。
 *
 * 列の導入前に記録された行（host が NULL）は当時どのホストで応答したかを
 * 復元できないため、既知ホストに混ぜず `UNRECORDED_LABEL` で分けて出す。
 */
function foldHosts(rows: BreakdownRow[]): Split[] {
  const splits = new Map<string, Split>(
    RECORDED_HOSTS.map((host) => [host, { label: host, human: 0, bot: 0 }]),
  )

  for (const row of rows) {
    const label = row.host ?? UNRECORDED_LABEL
    const split = splits.get(label) ?? { label, human: 0, bot: 0 }
    addTo(split, row)
    splits.set(label, split)
  }

  return [...splits.values()]
}

/** 集約済みの行を 1 軸へ畳む。件数の多い順、同数ならラベル順。 */
function foldSplits<T extends { is_bot: number; count: number }>(
  rows: T[],
  labelOf: (row: T) => string,
): Split[] {
  const byLabel = new Map<string, Split>()

  for (const row of rows) {
    const label = labelOf(row)
    const split = byLabel.get(label) ?? { label, human: 0, bot: 0 }
    addTo(split, row)
    byLabel.set(label, split)
  }

  return [...byLabel.values()].sort(
    (a, b) => b.human + b.bot - (a.human + a.bot) || a.label.localeCompare(b.label),
  )
}

/** 1 行ぶんを人間側・ロボット側のどちらかへ足す。判定は SQL 側の `is_bot`。 */
function addTo(split: Split, row: { is_bot: number; count: number }): void {
  if (row.is_bot === 1) split.bot += row.count
  else split.human += row.count
}

/**
 * 最新イベントの SELECT 句。**`recentEvents` と `eventsAfter` で共有する。**
 *
 * 2 箇所に書き写さない。両者は同じ `RecentEvent` を返す契約だが、`.all<RecentEvent>()`
 * のジェネリクスは実際の列を検査しないため、片方の列を落としてもコンパイルは通り、
 * 初期表示にはあるのに SSE で流れる行にだけ列が無い、という形で静かに壊れる
 * （実測: `eventsAfter` から page を落としても typecheck も既存テストも通った）。
 */
const RECENT_COLUMNS = 'id, timestamp, kind, version, country, os, page'

/** 最新イベント。SSE の差分取得と同じ形状・同じ絞り込み（人間のみ）で返す。 */
export async function recentEvents(db: D1Database, afterId = 0): Promise<RecentEvent[]> {
  const { results } = await db
    .prepare(
      `SELECT ${RECENT_COLUMNS}
       FROM events
       WHERE id > ? AND ${HUMAN_ONLY}
       ORDER BY id DESC
       LIMIT ?`,
    )
    .bind(afterId, RECENT_LIMIT)
    .all<RecentEvent>()

  return results
}

/**
 * 全指標ぶんの内訳を 1 本のクエリで取る（指標ごとに上位 N 件）。
 *
 * 指標ごとに引くと `(?1 IS NULL OR kind = ?1)` の形の述語で全表スキャンが指標の数
 * だけ並ぶ。指標を行に持たせて 1 本にまとめ、上位 N 件の切り出しは
 * `ROW_NUMBER()` の窓で指標ごとに行う（LIMIT だと 1 指標ぶんしか取れない）。
 */
async function metricBreakdown(
  db: D1Database,
  column: Extract<BreakdownColumn, 'os' | 'as_org'>,
): Promise<Map<MetricKey, Count[]>> {
  const { results } = await db
    .prepare(
      `WITH grouped AS (
         SELECT ${METRIC_EXPR} AS metric, ${column} AS label, COUNT(*) AS count
         FROM events
         WHERE ${column} IS NOT NULL AND ${HUMAN_ONLY}
         GROUP BY metric, label
       ),
       ranked AS (
         SELECT metric, label, count,
                ROW_NUMBER() OVER (PARTITION BY metric ORDER BY count DESC, label) AS position
         FROM grouped
         WHERE metric IS NOT NULL
       )
       SELECT metric, label, count
       FROM ranked
       WHERE position <= ${TOP_N}
       ORDER BY metric, position`,
    )
    .all<Count & { metric: MetricKey }>()

  const byMetric = new Map<MetricKey, Count[]>()
  for (const { metric, label, count } of results) {
    const counts = byMetric.get(metric) ?? []
    counts.push({ label, count })
    byMetric.set(metric, counts)
  }

  return byMetric
}

/** 指標ごとの OS 別・接続元組織別の内訳。合算しないため指標の意味が混ざらない。 */
async function kindBreakdowns(db: D1Database): Promise<Omit<KindBreakdown, 'total'>[]> {
  const [byOS, byAsOrg] = await Promise.all([
    metricBreakdown(db, 'os'),
    metricBreakdown(db, 'as_org'),
  ])

  return KIND_LABELS.map(({ kind, label }) => ({
    kind,
    label,
    byOS: byOS.get(kind) ?? [],
    byAsOrg: byAsOrg.get(kind) ?? [],
  }))
}

/** ダッシュボード初期表示用の集計一式。 */
export async function summarize(db: D1Database, now: number): Promise<Summary> {
  const [
    cumulative,
    today,
    daily,
    hourly,
    byVersion,
    byCountry,
    byReferrer,
    ua,
    breakdowns,
    recent,
    breakdownAxes,
  ] =
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
      kindBreakdowns(db),
      recentEvents(db),
      eventBreakdowns(db),
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
    visits: breakdownAxes.visits,
    hosts: breakdownAxes.byHost,
    fallbacks: breakdownAxes.byFallback,
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
      `SELECT ${RECENT_COLUMNS}
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
