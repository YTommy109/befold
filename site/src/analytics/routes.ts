/**
 * visit の言語・ページ別とホスト・フォールバック別の内訳を、1 本のクエリから畳む。
 * 直近の窓の集計は置かない（delivery.ts）。
 */

import { RECORDED_HOSTS } from '../lib/hosts'
import { NON_HUMAN_MATCH } from './access-class'
import { metricOf } from './metrics'
import { UNRECORDED_LABEL } from './shared'

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
  byHost: RouteTotals[]
  /** GitHub へ落ちた経路別（kind='github_fallback' のみ）。 */
  byFallback: RouteTotals[]
}

/**
 * 停止判断の対象になる経路 1 つぶん（旧ホスト・GitHub フォールバックの両方）。
 *
 * **かつてホスト別（`Split`）とフォールバック別（`FallbackSplit`）で型を分けていた。**
 * 理由は「0 件の既知ホストも行として残す表には最終発生時刻を持たない行が常に
 * 混ざる」であり、当時は妥当だった。TASK-489.5 で両表とも「この経路を止めて
 * よいか」を読むための同じ表になったので統一する。0 件の行は最終発生を `null` で
 * 表し、行を残すかどうかの違いは型ではなく畳む関数（`foldHosts` / `foldFallbacks`）が持つ。
 *
 * **`Split` を拡張しない。** あちらは `visits.byPage` などページ・言語別の内訳とも
 * 共有する型で、停止判断の列を足すと無関係な表がその値を運ぶことになる。
 *
 * 人間とロボットの最終発生を分けて持つ。停止条件は人間の有無で決まるのに、
 * 実測（2026-09-04）では旧ホストの直近の発生が Googlebot / Meta-ExternalAgent で、
 * 混ぜた最終発生では「まだ人間が来ている」と読めてしまう。
 *
 * 窓別の件数は人間だけを持つ。ロボットの推移は日次グラフで読む（表を 9 列にしない）。
 */
export type RouteTotals = {
  label: string
  human: number
  nonHuman: number
  /** 人間の最終発生（epoch ms）。一度も無ければ null。 */
  lastSeenHumanAt: number | null
  /** ロボット・自動アクセスの最終発生（epoch ms）。一度も無ければ null。 */
  lastSeenBotAt: number | null
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
function foldHosts(rows: BreakdownRow[]): RouteTotals[] {
  const splits = new Map<string, RouteTotals>(
    RECORDED_HOSTS.map((host) => [host, emptyRoute(host)]),
  )

  for (const row of rows) {
    const label = row.host ?? UNRECORDED_LABEL
    const split = splits.get(label) ?? emptyRoute(label)
    addRouteRow(split, row)
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
function foldFallbacks(rows: BreakdownRow[]): RouteTotals[] {
  const byLabel = new Map<string, RouteTotals>()

  for (const row of rows) {
    if (row.fallback === null) continue
    const split = byLabel.get(row.fallback) ?? emptyRoute(row.fallback)
    addRouteRow(split, row)
    byLabel.set(row.fallback, split)
  }

  return [...byLabel.values()].toSorted(
    (a, b) => b.human + b.nonHuman - (a.human + a.nonHuman) || a.label.localeCompare(b.label),
  )
}

/** 発生 0 件の経路。最終発生は「無い」ので null で、0 を入れて 1970 年を描かせない。 */
function emptyRoute(label: string): RouteTotals {
  return { label, human: 0, nonHuman: 0, lastSeenHumanAt: null, lastSeenBotAt: null }
}

/**
 * 集約済みの 1 行を経路へ足す。**最終発生は人間とロボットで別の列に入れる。**
 *
 * `is_non_human` は GROUP BY に入っているので、行そのものがどちらか一方に属する。
 * ここで混ぜると「停止条件は人間で決まるのに、最終発生はロボットが作っている」
 * 状態を読めなくする（実測 2026-09-04: 旧ホストの直近の発生は Googlebot と
 * Meta-ExternalAgent で、Sparkle は 08-21 が最後）。
 *
 * 窓別の件数はここでは足さない。全期間の集約行には窓の情報が無く、`deliveryWindow`
 * の別クエリが持つ（合流は `withWindowCounts`）。
 */
function addRouteRow(split: RouteTotals, row: BreakdownRow): void {
  addTo(split, row)
  if (row.is_non_human === 1) {
    split.lastSeenBotAt = Math.max(split.lastSeenBotAt ?? 0, row.last_seen_at)
  } else {
    split.lastSeenHumanAt = Math.max(split.lastSeenHumanAt ?? 0, row.last_seen_at)
  }
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
