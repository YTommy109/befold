/**
 * ダッシュボード向けの集計。規模が小さいため都度 GROUP BY で算出する。
 *
 * 日付・時間帯のバケットはすべて JST 基準（lib/jst.ts が唯一の定義元）。
 * 期間の絞り込みは `WHERE timestamp >= ?` だけで行い、idx_events_timestamp /
 * idx_events_kind が効く形を保つ。
 */

import { CHANNELS } from './lib/github'
import { RECORDED_HOSTS } from './lib/hosts'
import {
  JST_DAY_EXPR,
  JST_HOUR_EXPR,
  jstDayStart,
  jstDaysInWindow,
  jstWindowStart,
} from './lib/jst'
import { datacenterOrgMatch } from './lib/network'
import { BOT_PREFIX } from './lib/visitor'
import type { Channel, DownloadSource, EventKind, Page } from './schema'

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

/**
 * 日別のユニークアクセス元を数える母集団。
 *
 * **母集団を混ぜない。** `visit` はサイトを見に来た人、`update_check_*` は
 * アプリを起動してアップデート確認を飛ばした端末で、意味が違う。合算した
 * 「ユニーク」は、サイトも見てアプリも使った 1 人を 1 と数える一方で、
 * どちらの規模も表さない数になる。
 *
 * チャネルを分けるのは、実測で `update_check` の大半が develop（開発機）だった
 * ため。混ぜると利用者の規模を過大に見積もる。
 *
 * `update_check_unrecorded` は channel 列に値が無い行。0 件でも系列として残す
 * （`foldHosts` と同じ理由で、「まだ 0 だった」と「そもそも数えていない」を
 * 画面上で区別できなくしないため）。
 */
export type UniqueSourceKey = 'visit' | `update_check_${Channel}` | 'update_check_unrecorded'

/**
 * 母集団を SQL の条件式にする。**述語はここだけで組み立てる。**
 *
 * チャネル別の系列は `CHANNELS`（`lib/github.ts` が唯一の定義元）から生成する。
 * 手書きで並べるとチャネルを増やしたときに記録側だけが増え、新チャネルの
 * ユニーク数が画面のどこにも出ないまま落ちる。埋め込む値はこの定数だけで、
 * 外部入力は入らない。
 *
 * `visit` は page で絞らない。「ページアクセス」の指標が LP のみを数えるのとは
 * 意図が違い、こちらはサイトに来た人の規模を測るもの（当日集計の
 * `uniqueVisitors` も同じ扱い）。
 */
const UNIQUE_SOURCE_FILTERS: Record<UniqueSourceKey, string> = {
  visit: `kind = 'visit'`,
  ...(Object.fromEntries(
    CHANNELS.map((channel) => [
      `update_check_${channel}`,
      `kind = 'update_check' AND channel = '${channel}'`,
    ]),
  ) as Record<`update_check_${Channel}`, string>),
  update_check_unrecorded: `kind = 'update_check' AND channel IS NULL`,
}

/**
 * チャネル別系列の表示名。`Record<Channel, ...>` なので、チャネルを増やすと
 * ここに名前を書くまで型で落ちる（系列だけ無名で増えることがない）。
 */
const CHANNEL_LABELS: Record<Channel, string> = {
  stable: 'アプリ（stable）',
  develop: 'アプリ（develop）',
}

/** 母集団の並び順と表示名。集計・表示の双方でこの順を使う。 */
export const UNIQUE_SOURCE_LABELS: { key: UniqueSourceKey; label: string }[] = [
  { key: 'visit', label: 'サイト訪問' },
  ...CHANNELS.map((channel) => ({
    key: `update_check_${channel}` as const,
    label: CHANNEL_LABELS[channel],
  })),
  { key: 'update_check_unrecorded', label: 'アプリ（チャネル未記録）' },
]

/**
 * 稼働バージョン分布をチャネルごとに分ける鍵（TASK-491.2）。
 *
 * `channel` に値が無い行は `unrecorded` に入れる。0 件でも表として残すのは
 * `UNIQUE_SOURCE_LABELS` と同じ理由で、「まだ 0 だった」と「そもそも数えて
 * いない」を画面上で区別できなくしないため。
 */
export type RunningVersionKey = Channel | 'unrecorded'

/**
 * チャネル別の表の並び順と表示名。列挙は `CHANNELS` から生成する。
 *
 * 手書きで並べるとチャネルを増やしたときに記録側だけが増え、新チャネルの
 * 稼働バージョンが画面のどこにも出ないまま落ちる（`UNIQUE_SOURCE_LABELS` と
 * 同じ理由）。
 */
export const RUNNING_VERSION_LABELS: { key: RunningVersionKey; label: string }[] = [
  ...CHANNELS.map((channel) => ({
    key: channel as RunningVersionKey,
    label: CHANNEL_LABELS[channel],
  })),
  { key: 'unrecorded', label: 'アプリ（チャネル未記録）' },
]

/** チャネル別の稼働バージョン分布。 */
export type RunningVersions = Record<RunningVersionKey, Count[]>

/** 母集団ごとのユニークアクセス元数。 */
export type UniqueSources = Record<UniqueSourceKey, number>

/**
 * 母集団ごとの日次ユニーク数を取り出す SELECT 句。
 *
 * `COUNT(DISTINCT CASE WHEN ... END)` にするのは、母集団ごとにクエリを引かない
 * ため。日別推移のクエリに相乗りするので発行本数は増えない
 * （`query-count.test.ts` の上限がこの形を守る）。
 */
const UNIQUE_SOURCE_COLUMNS = uniqueSourceKeys()
  .map(
    (key) =>
      `COUNT(DISTINCT CASE WHEN ${UNIQUE_SOURCE_FILTERS[key]} THEN visitor_token END)` +
      ` AS unique_${key}`,
  )
  .join(', ')

type UniqueSourceRow = Partial<Record<`unique_${UniqueSourceKey}`, number | null>>

function uniqueSourceKeys(): UniqueSourceKey[] {
  return Object.keys(UNIQUE_SOURCE_FILTERS) as UniqueSourceKey[]
}

function toUniqueSources(row: UniqueSourceRow | null): UniqueSources {
  const sources = {} as UniqueSources
  for (const key of uniqueSourceKeys()) sources[key] = row?.[`unique_${key}`] ?? 0
  return sources
}

/**
 * 日別推移の 1 点。データが無い日も 0 で埋めて返す。
 *
 * `uniqueSources` は母集団別のユニークアクセス元数。全 kind を合算した数は
 * 持たない（母集団の違うものを足した値は、どの規模も表さない）。
 */
export type DailyPoint = { day: string; counts: KindCounts; uniqueSources: UniqueSources }

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

/**
 * ダッシュボードの面の識別子。**これが唯一の定義元。**
 *
 * ルートの生成・面ごとの集計・ナビゲーション・クエリ本数の上限テストは
 * すべてここから導く。面を別々に書き写すと、レジストリに載っていない面が
 * 上限テストの列挙から漏れ、「面を増やせば上限を回避できる」形に戻る。
 * 実行時に配列が要るので型ではなく値で持つ（`Record<DashboardPageKey, ...>` の
 * 網羅は型で検査される）。
 */
export const DASHBOARD_PAGE_KEYS = ['overview', 'users', 'traffic', 'delivery'] as const

export type DashboardPageKey = (typeof DASHBOARD_PAGE_KEYS)[number]

/** 面の定義。path はダッシュボードのルート配下の相対パス。 */
export type DashboardPage = { key: DashboardPageKey; path: string; title: string }

/**
 * 面の一覧。ルート生成・ナビゲーション・テストの列挙がこの配列を共有する。
 *
 * 概要面だけが SSE でライブ更新される。他の面は分析用のスナップショットで、
 * 更新されているように読ませないため SSE の状態表示も出さない。
 */
export const DASHBOARD_PAGES: readonly DashboardPage[] = [
  { key: 'overview', path: '/', title: '概要' },
  { key: 'users', path: '/users', title: '利用者' },
  { key: 'traffic', path: '/traffic', title: '流入' },
  { key: 'delivery', path: '/delivery', title: '配信' },
]

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
}

/** 流入面: どこから来て何をしたか。全期間の累計で見る。 */
export type TrafficSummary = {
  byVersion: Count[]
  byCountry: Count[]
  byReferrer: Count[]
  traffic: TrafficSplit
  visits: VisitBreakdowns
  perKind: KindBreakdown[]
}

/** 配信面: 配布ホストと旧経路・フォールバック。 */
export type DeliverySummary = {
  hosts: Split[]
  fallbacks: Split[]
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
/**
 * 内訳を切り出す上位 N 件。ダッシュボードの注記もこの値を読む（画面の説明と
 * 実際の切り出し件数がずれないように、数字を書き写さない）。
 */
export const TOP_N = 10
const RECENT_LIMIT = 20

/** SSE の 1 周期で流す新着イベントの上限。再開位置の判断に呼び出し側も使う。 */
export const STREAM_LIMIT = 100

/** 値が記録されていない行のラベル。列の導入前に記録された visit がここに入る。 */
export const UNRECORDED_LABEL = '未記録'

/**
 * ボット判定の SQL 側の表現。値の列挙は持たず接頭辞だけで分ける（lib/visitor.ts）。
 *
 * `COALESCE` を外さないこと。`ua_summary` は NULL 許容で、`NULL LIKE ...` は
 * NULL を返す。素の LIKE を WHERE に置くと、UA ヘッダの無いリクエストで
 * 記録された行が人間でもボットでもなく黙って全集計から消える。
 */
const BOT_MATCH = `COALESCE(ua_summary, '') LIKE '${BOT_PREFIX}%'`

/**
 * 接続元組織による自動アクセスの判定（ADR 0008）。定義元は `lib/network.ts`。
 *
 * UA 判定（`BOT_MATCH`）とは別の軸で、「UA はふつうのブラウザだが接続元が
 * データセンター」のアクセスを捕まえる。`as_org` は記録済みなので**全期間に
 * 遡って効く**（UA 分類は適用日以降しか効かない）。
 */
const DATACENTER_MATCH = datacenterOrgMatch()

/**
 * 人間の訪問ではないもの。UA でボットと分かるものと、接続元がデータセンターの
 * ものを合わせた条件。
 *
 * 2 軸を OR で束ねる形をここ以外に書かない。片方だけを見る箇所ができると、
 * 「人間側から引かれたのに自動アクセス側にも出ない」という**総和の合わない
 * 表示**になる（trafficSplit / eventBreakdowns がまさにその位置にある）。
 */
const NON_HUMAN_MATCH = `(${BOT_MATCH} OR ${DATACENTER_MATCH})`

/**
 * ロボットの巡回・自動アクセスを集計から外すための条件。集計クエリはこれを
 * WHERE へ足す。
 *
 * 除外の条件はこの 1 箇所だけに置く（集計ごとに書き写さない）。この規約は
 * `analytics.test.ts` の「FROM events を含むクエリは HUMAN_ONLY を含むか、
 * 意図的な除外リストに載っているか」を検査するテストが担保する。
 *
 * UA 分類（TASK-386）の適用前に記録された行は種類が分からず 'other' または NULL に
 * 丸まっており、UA の軸では人間側に残る。遡って分類し直す材料（完全な UA）を
 * 保存していないため。接続元組織の軸にはこの制約が無い。この非対称は
 * ダッシュボードの注記で示す。
 */
const HUMAN_ONLY = `NOT ${NON_HUMAN_MATCH}`

/**
 * 1 行がどの区分かを返す SQL 式。内訳を区分ごとに 1 本のクエリで取るために使う。
 *
 * 判定の順序が意味を持つ。UA でボットと分かるものを先に見る——データセンターから
 * 来る Googlebot を「データセンター」に寄せると、ADR 0004 が測りたかった
 * 「AI クローラの到来量」がクローラ名の内訳から消えるため。
 */
const TRAFFIC_CLASS_EXPR =
  `CASE WHEN ${BOT_MATCH} THEN '${'bot' satisfies TrafficClass}'` +
  ` WHEN ${DATACENTER_MATCH} THEN '${'datacenter' satisfies TrafficClass}'` +
  ` ELSE '${'human' satisfies TrafficClass}' END`

/**
 * 区分ごとの内訳ラベルを選ぶ SQL 式。
 *
 * データセンター区分だけ `as_org` を出す。UA を出しても `Chrome` や `other` が
 * 並ぶだけで、どこから来たのかが読めないため。値が無い行は「未記録」に寄せる
 * （区分から黙って落とさない）。
 */
const TRAFFIC_LABEL_EXPR =
  `CASE WHEN ${DATACENTER_MATCH} AND NOT ${BOT_MATCH}` +
  ` THEN COALESCE(as_org, '${UNRECORDED_LABEL}')` +
  ` ELSE COALESCE(ua_summary, '${UNRECORDED_LABEL}') END`

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
              ${UNIQUE_SOURCE_COLUMNS}
       FROM events
       WHERE timestamp >= ? AND ${HUMAN_ONLY}
       GROUP BY day
       ORDER BY day`,
    )
    .bind(jstWindowStart(now, days))
    .all<KindCountRow & UniqueSourceRow & { day: string }>()

  const byDay = new Map(results.map((row) => [row.day, row]))

  return jstDaysInWindow(now, days).map((day) => {
    const row = byDay.get(day) ?? null
    return { day, counts: toKindCounts(row), uniqueSources: toUniqueSources(row) }
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
 * アクセスの区分。人間・UA で分かるロボット・接続元がデータセンターの 3 つ。
 *
 * `datacenter` を `bot` に混ぜない。判定の軸（UA / 接続元組織）も、遡って効くか
 * どうかも違うため、画面上で分けて読めないと「いつからの数字か」が分からなくなる。
 */
export type TrafficClass = 'human' | 'bot' | 'datacenter'

const TRAFFIC_CLASSES: TrafficClass[] = ['human', 'bot', 'datacenter']

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
 * 1 つの区分の、人間とそれ以外の件数。
 *
 * `nonHuman` は UA で分かるロボットと、接続元がデータセンターのものの合算。
 * `bot` という名前にしない——`HUMAN_ONLY` が外す対象と同じ集合であることを
 * 名前で示す（かつて `bot` だったので、意味が広がったことが型で分かる）。
 */
export type Split = { label: string; human: number; nonHuman: number }

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
              COUNT(*) AS count, ${NON_HUMAN_MATCH} AS is_non_human
       FROM events
       GROUP BY kind, page, display_lang, browser_lang, host, fallback, is_non_human`,
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
  is_non_human: number
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
    RECORDED_HOSTS.map((host) => [host, { label: host, human: 0, nonHuman: 0 }]),
  )

  for (const row of rows) {
    const label = row.host ?? UNRECORDED_LABEL
    const split = splits.get(label) ?? { label, human: 0, nonHuman: 0 }
    addTo(split, row)
    splits.set(label, split)
  }

  return [...splits.values()]
}

/** 集約済みの行を 1 軸へ畳む。件数の多い順、同数ならラベル順。 */
function foldSplits<T extends { is_non_human: number; count: number }>(
  rows: T[],
  labelOf: (row: T) => string,
): Split[] {
  const byLabel = new Map<string, Split>()

  for (const row of rows) {
    const label = labelOf(row)
    const split = byLabel.get(label) ?? { label, human: 0, nonHuman: 0 }
    addTo(split, row)
    byLabel.set(label, split)
  }

  return [...byLabel.values()].toSorted(
    (a, b) => b.human + b.nonHuman - (a.human + a.nonHuman) || a.label.localeCompare(b.label),
  )
}

/** 1 行ぶんを人間側・自動アクセス側のどちらかへ足す。判定は SQL 側の `is_non_human`。 */
function addTo(split: Split, row: { is_non_human: number; count: number }): void {
  if (row.is_non_human === 1) split.nonHuman += row.count
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
 * 指標別の内訳を取る軸。SQL へ差し込むため、外部入力を受けない固定の集合に限る。
 *
 * 軸を増やしてもクエリは 1 本のまま（`metricBreakdowns` が `UNION ALL` で
 * 軸を行に持たせる）。軸ごとに 1 本ずつ引く形へ戻すと `query-count.test.ts` の
 * 上限で落ちる。
 */
const METRIC_BREAKDOWN_AXES = ['os', 'as_org'] as const

type MetricBreakdownAxis = (typeof METRIC_BREAKDOWN_AXES)[number]

/**
 * 全指標・全軸ぶんの内訳を 1 本のクエリで取る（指標ごと・軸ごとに上位 N 件）。
 *
 * 指標ごとに引くと `(?1 IS NULL OR kind = ?1)` の形の述語で全表スキャンが指標の数
 * だけ並ぶ。指標を行に持たせて 1 本にまとめ、上位 N 件の切り出しは
 * `ROW_NUMBER()` の窓で指標ごとに行う（LIMIT だと 1 指標ぶんしか取れない）。
 *
 * 軸（os / as_org）も同じ理由で行に持たせる。`trafficSplit` の区分・
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
async function runningVersionBreakdown(db: D1Database, now: number): Promise<RunningVersions> {
  const { results } = await db
    .prepare(
      `WITH grouped AS (
         SELECT COALESCE(channel, 'unrecorded') AS channel, app_version AS label,
                COUNT(DISTINCT visitor_token) AS count
         FROM events
         WHERE app_version IS NOT NULL AND timestamp >= ?
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
    .all<Count & { channel: RunningVersionKey }>()

  // 0 件のチャネルも空配列で残す（表そのものを消さないため）。
  const byChannel = {} as RunningVersions
  for (const { key } of RUNNING_VERSION_LABELS) byChannel[key] = []
  for (const { channel, label, count } of results) {
    byChannel[channel]?.push({ label, count })
  }

  return byChannel
}

/** 指標ごとの OS 別・接続元組織別の内訳。合算しないため指標の意味が混ざらない。 */
async function kindBreakdowns(db: D1Database): Promise<Omit<KindBreakdown, 'total'>[]> {
  const byAxis = await metricBreakdowns(db)
  const byOS = byAxis.get('os') ?? new Map<MetricKey, Count[]>()
  const byAsOrg = byAxis.get('as_org') ?? new Map<MetricKey, Count[]>()

  return KIND_LABELS.map(({ kind, label }) => ({
    kind,
    label,
    byOS: byOS.get(kind) ?? [],
    byAsOrg: byAsOrg.get(kind) ?? [],
  }))
}

/** ダッシュボード初期表示用の集計一式。 */
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
  const [daily, hourly, runningVersions] = await Promise.all([
    dailySeries(db, now),
    hourlyDistribution(db, now),
    runningVersionBreakdown(db, now),
  ])

  return { windowDays: DAILY_WINDOW_DAYS, daily, hourly, runningVersions }
}

/**
 * 流入面の集計（8 クエリ）。
 *
 * `perKind` の総数は全期間の累計から取るため、この面も cumulativeTotals を引く。
 * ua_summary の内訳は AI クローラ（GPTBot / ClaudeBot 等）の到来量を実測する
 * ために持つ。TASK-360 で見送った llms.txt の要否判断に使う。データセンター
 * 区分の内訳は接続元組織で、除外した量が画面から消えないようにするもの（ADR 0008）。
 */
export async function summarizeTraffic(db: D1Database): Promise<TrafficSummary> {
  const [cumulative, byVersion, byCountry, byReferrer, traffic, breakdowns, breakdownAxes] =
    await Promise.all([
      cumulativeTotals(db),
      breakdown(db, 'version', 'download'),
      breakdown(db, 'country'),
      breakdown(db, 'referrer'),
      trafficSplit(db),
      kindBreakdowns(db),
      eventBreakdowns(db),
    ])

  return {
    byVersion,
    byCountry,
    byReferrer,
    traffic,
    visits: breakdownAxes.visits,
    // 要素数は指標の数（KIND_LABELS）に固定で、ここでの spread が効いてくる規模に
    // ならない。Object.assign へ書き換えると読みにくくなるだけなので許す。
    // oxlint-disable-next-line oxc/no-map-spread
    perKind: breakdowns.map((entry) => ({ ...entry, total: cumulative.counts[entry.kind] })),
  }
}

/** 配信面の集計（1 クエリ）。 */
export async function summarizeDelivery(db: D1Database): Promise<DeliverySummary> {
  const breakdownAxes = await eventBreakdowns(db)

  return { hosts: breakdownAxes.byHost, fallbacks: breakdownAxes.byFallback }
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
