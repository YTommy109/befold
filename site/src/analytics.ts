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
  DAY_MS,
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
export type MetricKey = EventKind | 'update_download' | 'archive_download'

/**
 * 指標を events の行へ落とすための述語。
 *
 * `source` が NULL の行は source 列の導入前に記録されたもので、当時 Worker を
 * 通るダウンロードは LP 経由しか存在しなかった。`COALESCE(source, 'lp')` は
 * その事実を表しており、過去データを含めた `download` 系列の意味を保つ。
 */
type MetricFilter = { kind: EventKind; source: DownloadSource | null; page: Page | null }

const METRIC_FILTERS: Record<MetricKey, MetricFilter> = {
  // 「ページビュー」はサイト全体への訪問を数える（LP・features・releases・
  // usecases・記事）。LP 単独の数は指標として持たず、流入面「ページ別の訪問」の
  // 「/」行で読む（TASK-551）。visit 系のキーを 2 つに割ると `METRIC_EXPR` の
  // CASE 先頭一致で LP の行が片方へ吸われ、`metricBreakdowns` 側が常に 0 になる。
  visit: { kind: 'visit', source: null, page: null },
  download: { kind: 'download', source: 'lp', page: null },
  update_download: { kind: 'download', source: 'sparkle', page: null },
  // 旧バージョン一覧（/releases）からのダウンロード。新規獲得（lp）と混ぜると
  // 「最新版が何件落とされたか」が読めなくなり、自動更新（sparkle）と混ぜると
  // 人間が意図して戻した行為が更新として数えられる。
  archive_download: { kind: 'download', source: 'archive', page: null },
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
 * 同じ `kind='download'` を `source` で分けた内訳。**`METRIC_FILTERS` から導く。**
 *
 * 画面はこの集合を「合計と内訳」として扱う。手で列挙すると、ダウンロード経路を
 * 足したときに合計へ入らない系列が黙って生まれる（合計が内訳の和にならない）。
 */
export const DOWNLOAD_METRICS: ReadonlySet<MetricKey> = new Set(
  metricKeys().filter((metric) => METRIC_FILTERS[metric].kind === 'download'),
)

/**
 * 概要面のカード・推移グラフに出す指標。**概要面の描画だけがこれで絞る。**
 *
 * `KIND_LABELS` からダウンロード内訳を外す形にはしない。`KIND_LABELS` は概要
 * カード・概要推移グラフ・利用者面の時間帯分布・流入面 `perKind` の 4 箇所が
 * 消費しており、そこを削ると概要面以外の 3 箇所からも黙って消えるため
 * （TASK-551）。ダウンロードは合計 1 枚だけを概要に残し、内訳は流入面
 * 「内訳（全期間の累計）」で読む。
 *
 * `KIND_LABELS` の部分集合であることは `analytics.test.ts` が検査する。
 */
export const OVERVIEW_METRICS: ReadonlySet<MetricKey> = new Set<MetricKey>(['visit'])

/** ダウンロード系の合計。内訳が互いに素なので、単純な和で総ダウンロード数になる。 */
export function downloadTotal(counts: KindCounts): number {
  return [...DOWNLOAD_METRICS].reduce((sum, metric) => sum + counts[metric], 0)
}

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
 * `metricExpression` が SQL 側でやる判定を、行を手元に持っている側で行う版。
 *
 * 全 kind をまとめて引いてから TS 側で軸ごとに畳む集計（`eventBreakdowns`）が
 * 「その行はどの指標か」を必要とする。そこで `row.kind === 'visit'` と書くと、
 * 指標の述語の定義元が `METRIC_FILTERS` の外にもう 1 つできる。三条件
 * （kind / source / page）の対応は上の式と 1 対 1 で、両者が同じ行に同じ答えを
 * 返すことは `analytics.test.ts` が全 `MetricKey` × 列の組み合わせで検査する。
 *
 * NULL の丸め（`COALESCE`）も SQL 側と揃える。`source` が NULL の行は列の導入前の
 * LP 経由、`page` が NULL の行は列の導入前の visit（当時は LP のみ）。
 */
function matchesMetric(row: MetricRow, { kind, source, page }: MetricFilter): boolean {
  if (row.kind !== kind) return false
  if (source !== null && (row.source ?? 'lp') !== source) return false
  if (page !== null && (row.page ?? '/') !== page) return false
  return true
}

/**
 * 指標の判定にかけられる行。列が無い行（その kind では常に NULL）は省いてよい。
 *
 * 省いた列を条件に持つ指標へ当てると「その列が NULL の行」と同じ扱いになるため、
 * 呼び出し側は自分が渡す行に必要な列が載っていることを型で示すことになる。
 */
type MetricRow = { kind: string; source?: string | null; page?: string | null }

/**
 * 行がどの指標に当たるかを返す（どれにも当たらなければ null）。`METRIC_EXPR` の TS 版。
 *
 * 先頭一致で決めるのも SQL の `CASE` と同じ。互いに素でない述語を足したときに
 * 両者の答えがずれないよう、評価順まで揃える。
 */
export function metricOf(row: MetricRow): MetricKey | null {
  return metricKeys().find((metric) => matchesMetric(row, METRIC_FILTERS[metric])) ?? null
}

/**
 * 指標を SQL 側で判定する式（どの指標にも当たらない行は NULL）。
 *
 * 内訳を指標ごとに 1 本ずつ引くと指標の数だけ全表スキャンが増えるため、指標を行に
 * 持たせて 1 本にまとめるための式。埋め込む値は `METRIC_FILTERS` の定数だけで、
 * 外部入力は入らない。判定の定義元を二重に持たないよう、条件はここで組み立てる。
 */
export const METRIC_EXPR = `CASE ${Object.entries(METRIC_FILTERS)
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
 * `visit` は page で絞らない。「ページビュー」の指標と範囲は同じ（サイト全体）だが、
 * こちらが数えるのは延べ回数ではなくアクセス元の異なり数で、サイトに来た人の規模を
 * 測るもの（当日集計の `uniqueVisitors` も同じ扱い）。
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

/** 稼働バージョン分布の鍵。develop を含まない（{@link RUNNING_VERSION_TABLE_LABELS}）。 */
export type RunningVersionTableKey = Exclude<RunningVersionKey, 'develop'>

/**
 * 稼働バージョン分布が対象にするチャネル（`develop` を除いたもの）。
 *
 * develop は作者の開発機（個人 2 台 + 職場 1 台）しか映らない。しかも数える
 * 単位は「アクセス元×日」なので、同じ 1 台が回線や日をまたぐたびに増える。
 * 「他に利用者がいるのか」を読み取る用途には使えず、外部利用者の分布を見る
 * stable の表の隣に並ぶと誤読を招くだけなので、この表からは外す。
 *
 * 転換率（`RUNNING_VERSION_LABELS` を使う「確認 → 更新」）は develop も残す。
 * あちらは自分の機体でも更新経路が生きているかの確認に使える。
 */
export const RUNNING_VERSION_TABLE_LABELS: { key: RunningVersionTableKey; label: string }[] =
  RUNNING_VERSION_LABELS.filter(
    (entry): entry is { key: RunningVersionTableKey; label: string } => entry.key !== 'develop',
  )

/** チャネル別の稼働バージョン分布。 */
export type RunningVersions = Record<RunningVersionTableKey, Count[]>

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
  /** バージョン別。version 列を持たない指標（visit など）では空になる。 */
  byVersion: Count[]
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
export const DASHBOARD_PAGE_KEYS = ['overview', 'users', 'traffic', 'delivery', 'events'] as const

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
  { key: 'events', path: '/events', title: 'イベント' },
]

/** 概要面: 全期間と当日の総数、日毎の推移、最新イベント。 */
export type OverviewSummary = {
  windowDays: number
  cumulative: CumulativeTotals
  today: TodayTotals
  daily: DailyPoint[]
  recent: RecentEvent[]
}

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
  hosts: Split[]
  fallbacks: FallbackSplit[]
}

/**
 * 指標として並べる順序と表示名。ページ表示・集計の双方でこの順を使う。
 *
 * ダウンロード系の 3 つは連続して並べ、ラベルの接頭辞を「ダウンロード」で
 * 揃える。これらは `kind='download'` を `source` で分けた互いに素な内訳で、
 * どれかがどれかを含むことはない。かつて先頭が単に「ダウンロード」で、内訳の
 * 1 つ（旧バージョン）がそれを上回る並びになると、部分集合が本体を超えたように
 * 読めた（「本日 ダウンロード 1 / 旧バージョンのダウンロード 6」の報告）。
 * カードは `DOWNLOAD_METRICS` の合計を併記して、3 つが内訳であることを示す。
 */
export const KIND_LABELS: { kind: MetricKey; label: string }[] = [
  { kind: 'visit', label: 'ページビュー' },
  { kind: 'update_check', label: 'アップデート確認' },
  { kind: 'download', label: 'ダウンロード（LP）' },
  { kind: 'update_download', label: 'ダウンロード（自動更新）' },
  { kind: 'archive_download', label: 'ダウンロード（旧バージョン）' },
]

/** 日別推移・時間帯分布が対象にする窓（当日を含む直近 N 日）。 */
export const DAILY_WINDOW_DAYS = 14
/**
 * 内訳を切り出す上位 N 件。ダッシュボードの注記もこの値を読む（画面の説明と
 * 実際の切り出し件数がずれないように、数字を書き写さない）。
 */
export const TOP_N = 10
const RECENT_LIMIT = 20

/**
 * イベント面の 1 ページあたりの件数。
 *
 * 概要面の `RECENT_LIMIT`（20 件）とは別の定数にする。概要面は「いま何が
 * 起きているか」を一目で見るための短い一覧で、イベント面は過去へ遡るための
 * 一覧なので、片方を変えたときにもう片方まで動くと困る。
 */
export const EVENTS_PAGE_LIMIT = 100

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

/** 指定カラムの内訳（上位 N 件、NULL は除外）。 */
async function breakdown(db: D1Database, column: BreakdownColumn): Promise<Count[]> {
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
type ReferrerScope = 'all' | 'download'

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
async function referrerBreakdowns(db: D1Database): Promise<Record<ReferrerScope, Count[]>> {
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
  byFallback: FallbackSplit[]
}

/**
 * フォールバック経路 1 つぶんの件数と、**最後に発生した時刻**（epoch ms）。
 *
 * 累計だけでは「直近は落ちていない」が読めない。一度でも発生すると件数は
 * 二度と減らないため、GitHub 経路を止めてよいか（ADR 0007 / TASK-489）の判断は
 * 「最後にいつ落ちたか」でしか付かない。ホスト別（`Split`）にこの列を足さないのは、
 * あちらが「0 件の既知ホストも行として残す」表で、最終発生時刻を持たない行が
 * 常に混ざるため（意味の違う 2 つの表を同じ型にすると片方だけ直る）。
 *
 * `null` にはならない。この配列は発生した行だけから作る。
 */
export type FallbackSplit = Split & { lastSeenAt: number }

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
 * このクエリは kind を絞らないため、丸めは visit の行だけを対象に TS 側
 * （`visitRows`）で行う。**その「visit かどうか」は `metricOf` で決める**——
 * ここで `row.kind === 'visit'` と書くと、指標の述語が `METRIC_FILTERS` の外へ
 * もう 1 つ増える（TASK-553）。
 *
 * 一方 `page ?? '/'` の丸めは指標の述語ではなく**軸ラベルの丸め**で、
 * `METRIC_FILTERS` からは導かない。`METRIC_FILTERS.visit` はサイト全体の訪問を
 * 数えるので page 条件を持たない（TASK-551）が、ページ別の表では列の導入前の行を
 * どこかの行に置く必要がある。結果として「/」の行は「LP への訪問」と
 * 「列の導入前の訪問」の和になる。
 *
 * ボット判定は `BOT_MATCH` をそのまま使う。ここで新しい判定を書かない——
 * 判定の定義元が増えると、`BOT_TOKENS` を足したときに片方だけ直る。
 */
export async function eventBreakdowns(db: D1Database): Promise<EventBreakdowns> {
  const { results } = await db
    .prepare(
      `SELECT kind, page, display_lang, browser_lang, host, fallback,
              COUNT(*) AS count, MAX(timestamp) AS last_seen_at,
              ${NON_HUMAN_MATCH} AS is_non_human
       FROM events
       GROUP BY kind, page, display_lang, browser_lang, host, fallback, is_non_human`,
    )
    .all<BreakdownRow>()

  const visitRows = results.filter((row) => metricOf(row) === 'visit')

  return {
    visits: {
      byPage: foldSplits(visitRows, (row) => row.page ?? '/'),
      byDisplayLang: foldSplits(visitRows, (row) => row.display_lang ?? UNRECORDED_LABEL),
      byBrowserLang: foldSplits(visitRows, (row) => row.browser_lang ?? UNRECORDED_LABEL),
    },
    byHost: foldHosts(results),
    byFallback: foldFallbacks(results),
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
  last_seen_at: number
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

/**
 * フォールバックを経路別に畳む。件数に加えて**最後に発生した時刻**を持たせる。
 *
 * `foldSplits` に相乗りさせない。あちらは件数だけを畳む汎用の関数で、
 * 最終発生時刻を optional で足すと使う側が「ある表と無い表」を意識することになる。
 *
 * 行が無い経路は行として出さない（ホスト別と逆）。まだ一度も落ちていない経路に
 * 「最後に発生した時刻」は無く、0 の行を作ると空欄の意味を説明する羽目になる。
 */
function foldFallbacks(rows: BreakdownRow[]): FallbackSplit[] {
  const byLabel = new Map<string, FallbackSplit>()

  for (const row of rows) {
    if (row.fallback === null) continue
    const split = byLabel.get(row.fallback) ?? {
      label: row.fallback,
      human: 0,
      nonHuman: 0,
      lastSeenAt: 0,
    }
    addTo(split, row)
    split.lastSeenAt = Math.max(split.lastSeenAt, row.last_seen_at)
    byLabel.set(row.fallback, split)
  }

  return [...byLabel.values()].toSorted(
    (a, b) => b.human + b.nonHuman - (a.human + a.nonHuman) || a.label.localeCompare(b.label),
  )
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
 * 最新イベントの SELECT 句。**`recentEvents`・`eventsAfter`・`eventPage` で共有する。**
 *
 * 3 箇所に書き写さない。どれも同じ `RecentEvent` を返す契約だが、`.all<RecentEvent>()`
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
 * イベント面のページ送りの向きと基準 id。
 *
 * `OFFSET` は使わない。イベントは常に先頭（新しい側）へ挿入されるため、
 * オフセットで数えるとページを送っている間に境界がずれ、同じ行が 2 度出たり
 * 抜けたりする。基準を id に置けば、その後に何件挿入されても
 * 「この id より古い 100 件」は変わらない。
 */
export type EventCursor = { direction: 'older' | 'newer'; id: number }

/**
 * イベント面の 1 ページ分。
 *
 * `olderCursor` / `newerCursor` は、その向きへさらにページがあるときだけ入る
 * （そのまま「前へ」「次へ」のリンクの有無になる）。
 */
export type EventPage = {
  events: RecentEvent[]
  olderCursor?: number
  newerCursor?: number
}

/**
 * イベント面の 1 ページを引く（新しい順、人間のみ）。
 *
 * **上限より 1 件多く引いて、次のページがあるかを同じクエリで確定させる。**
 * 「次があるか」を別のクエリ（COUNT など）で問い直すと 1 面 2 本になり、
 * `query-count.test.ts` の上限の意味が薄れる。
 *
 * 逆向きのカーソルは、そちらから来たことで存在が確定する。`older` へ送った
 * ときの基準 id は直前のページに表示されていた実在の行なので、`newer` を
 * たどれば必ずその行が返る（URL を手で書き換えれば空になりうるが、その場合も
 * 0 件の表示になるだけで壊れない）。
 */
export async function eventPage(db: D1Database, cursor?: EventCursor): Promise<EventPage> {
  const newer = cursor?.direction === 'newer'
  // ボットの除外は `HUMAN_ONLY` を SQL へ直に埋める（条件の書き写しを禁じる
  // 構造ガードが、events を読むクエリの近くにその参照を求めている）。
  // ここで組み立てるのは id の境界だけ。
  const bounded = cursor === undefined ? '' : `id ${newer ? '>' : '<'} ? AND `
  const bindings = cursor === undefined ? [] : [cursor.id]
  // 新しい側へ戻るときだけ昇順で引き、返してから並びを新しい順へ戻す。
  // 降順のまま `id > ?` を引くと、基準のすぐ上ではなく最新側の 100 件が返り、
  // 間のページが飛ぶ。
  const { results } = await db
    .prepare(
      `SELECT ${RECENT_COLUMNS}
       FROM events
       WHERE ${bounded}${HUMAN_ONLY}
       ORDER BY id ${newer ? 'ASC' : 'DESC'}
       LIMIT ?`,
    )
    .bind(...bindings, EVENTS_PAGE_LIMIT + 1)
    .all<RecentEvent>()

  const hasMore = results.length > EVENTS_PAGE_LIMIT
  const page = results.slice(0, EVENTS_PAGE_LIMIT)
  const events = newer ? page.toReversed() : page
  const first = events[0]
  const last = events.at(-1)

  return {
    events,
    // 引いた向きは実件数で確定する。逆向きは、そこから来ていれば必ず存在する。
    olderCursor: (newer ? cursor !== undefined : hasMore) ? last?.id : undefined,
    newerCursor: (newer ? hasMore : cursor !== undefined) ? first?.id : undefined,
  }
}

/**
 * クエリパラメータからページ送りの基準を読む。
 *
 * `parseInt` ではなく `Number` を使う（'12abc' を 12 として受け取らない）。
 * 読めない値・空文字・負の値は基準無し（＝最新のページ）に倒す。空文字を弾かないと
 * `Number('')` が 0 になり、`?after=` だけの URL が「id 0 より新しい」＝最新の
 * ページに化ける（先頭ページと同じ内容だが「新しい側へ戻れる」と表示される）。
 * `before` と `after` が
 * 同時に来たら `before` を採る（片方だけを見て両方指定を静かに無視しない）。
 */
export function parseEventCursor(query: {
  before?: string
  after?: string
}): EventCursor | undefined {
  const before = query.before ?? ''
  const after = query.after ?? ''
  const direction = before.length === 0 && after.length > 0 ? 'newer' : 'older'
  const raw = direction === 'newer' ? after : before
  if (raw.length === 0) return undefined

  const id = Math.trunc(Number(raw))
  if (!Number.isFinite(id) || id < 0) return undefined

  return { direction, id }
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
async function updateAdoption(
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

/** 指標ごとの OS 別・接続元組織別・バージョン別の内訳。合算しないため指標の意味が混ざらない。 */
async function kindBreakdowns(db: D1Database): Promise<Omit<KindBreakdown, 'total'>[]> {
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

/**
 * バージョン別の内訳を出す指標。**`METRIC_FILTERS` から導く。**
 *
 * version 列を持つのは download 系だけで、visit や update_check の行では常に
 * NULL になる。「表が空なら出さない」という形にすると、データがまだ無いだけの
 * 指標まで消えて、0 件であることが読めなくなる（0 件は 0 件として見せる）。
 */
export const VERSION_BREAKDOWN_METRICS: ReadonlySet<MetricKey> = DOWNLOAD_METRICS

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
