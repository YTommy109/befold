/**
 * 指標（MetricKey）の定義と、述語の SQL / TS 両版、指標ごとの件数列。
 * 指標の述語はここだけで組み立てる。クエリ本体は置かない。
 */

import type { DownloadSource, EventKind, Page } from '../schema'

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
export type MetricFilter = { kind: EventKind; source: DownloadSource | null; page: Page | null }

export const METRIC_FILTERS: Record<MetricKey, MetricFilter> = {
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

/**
 * 既存ユーザの自動更新（Sparkle）。新規獲得ではないので、新規ダウンロードとは
 * 分けて数える。
 */
export function updateDownloads(counts: KindCounts): number {
  return counts.update_download
}

/**
 * 新規ダウンロード = 配布 LP 経由（source='lp'）だけ。旧バージョン（archive）を
 * 含めない。archive は DMG の URL を直接取得するボットが大半（実測: 累計 862 件中
 * 582 件）で、ページを経由しないため、混ぜると「ページビューより新規ダウンロードが
 * 多い」という成立しない並びになる。内訳は流入面で読む。
 */
export function newDownloads(counts: KindCounts): number {
  return counts.download
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
export function metricExpression({ kind, source, page }: MetricFilter): string {
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

/**
 * 種別ごとの件数を 1 行から取り出すための SELECT 句。
 *
 * 述語は書き写さず `metricExpression` から組み立てる。列名は指標キーそのものを
 * 使い、`toKindCounts` の対応表も指標キーから作る（片方だけ増えると型で落ちる）。
 */
export const KIND_COUNT_COLUMNS = metricKeys()
  .map((metric) => `SUM(${metricExpression(METRIC_FILTERS[metric])}) AS ${metric}`)
  .join(', ')

export type KindCountRow = Partial<Record<MetricKey, number | null>>

export function metricKeys(): MetricKey[] {
  return Object.keys(METRIC_FILTERS) as MetricKey[]
}

export function toKindCounts(row: KindCountRow | null): KindCounts {
  const counts = {} as KindCounts
  for (const metric of metricKeys()) counts[metric] = row?.[metric] ?? 0
  return counts
}

/**
 * バージョン別の内訳を出す指標。**`METRIC_FILTERS` から導く。**
 *
 * version 列を持つのは download 系だけで、visit や update_check の行では常に
 * NULL になる。「表が空なら出さない」という形にすると、データがまだ無いだけの
 * 指標まで消えて、0 件であることが読めなくなる（0 件は 0 件として見せる）。
 */
export const VERSION_BREAKDOWN_METRICS: ReadonlySet<MetricKey> = DOWNLOAD_METRICS
