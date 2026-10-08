import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'

import {
  cumulativeTotals,
  summarizeDelivery,
  todayTotals,
  eventsAfter,
  eventPage,
  parseEventCursor,
  EVENTS_PAGE_LIMIT,
  recentEvents,
  eventBreakdowns,
  UNRECORDED_LABEL,
  METRIC_EXPR,
  metricOf,
  DELIVERY_WINDOW_DAYS,
  DELIVERY_RECENT_DAYS,
} from '../src/analytics'
import { CANONICAL_HOST, LEGACY_HOST, RECORDED_HOSTS } from '../src/lib/hosts'
import { DAY_MS, jstDayKey } from '../src/lib/jst'
import { clearEvents, NOW, summarizeAll } from './analytics-helpers'

afterEach(clearEvents)

describe('ページの分離', () => {
  /** page を明示して visit を 1 件記録する。page=null は列の導入前に記録された行。 */
  async function insertVisit(page: string | null, ts: number = NOW): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, visitor_token, page) VALUES (?, ?, ?, ?)',
    )
      .bind(ts, 'visit', `visitor-${page ?? 'legacy'}`, page)
      .run()
  }

  it('「ページビュー」の全系列がサイト全体の訪問を数える', async () => {
    // 指標の述語は METRIC_FILTERS 1 箇所から組み立てる決まりで、累計・当日・
    // 日次・時間帯・内訳がそれを共有する。どれか 1 つが述語を書き写す形（LP 限定）
    // へ戻ると下層ページがここから消えるので、全系列をまとめて固定する。
    await insertVisit('/')
    await insertVisit('/features')
    await insertVisit('/features')

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.cumulative.counts.visit).toBe(3)
    expect(summary.today.counts.visit).toBe(3)
    expect(summary.daily.at(-1)?.counts.visit).toBe(3)
    expect(summary.hourly.reduce((total, hour) => total + hour.counts.visit, 0)).toBe(3)
    expect(summary.perKind.find((entry) => entry.kind === 'visit')?.total).toBe(3)
  })

  it('記事や活用例ページへの訪問がページビューに反映される', async () => {
    // TASK-551 の発端。イベント面には出るのに概要面が動かない、という形の退行。
    await insertVisit('/usecases/medical-expenses')

    expect((await cumulativeTotals(env.DB)).counts.visit).toBe(1)
  })

  it('page 列の導入前に記録された visit（page が NULL）も数える', async () => {
    // 当時 visit を計上していたのは LP だけ（src/routes/public.tsx）。述語から
    // page 条件が消えても旧行が落ちないことを固定する。
    await insertVisit(null)

    expect((await cumulativeTotals(env.DB)).counts.visit).toBe(1)
  })

  it('日次ユニーク訪問者はページで絞らない（サイト全体の訪問者数）', async () => {
    // 指標ごとの件数（延べ）と COUNT(DISTINCT visitor_token)（異なり数）は
    // 単位が違う。範囲は同じ「サイト全体」で、母数が食い違わないことを固定する。
    await insertVisit('/')
    await insertVisit('/features')

    const totals = await todayTotals(env.DB, NOW)

    expect(totals.counts.visit).toBe(2)
    expect(totals.uniqueVisitors).toBe(2)
  })
})

describe('指標の述語の定義元', () => {
  /**
   * `src/analytics/` からコメントを落としたソース。構造ガードが doc コメント中の
   * 例示（`kind = 'visit'` のような説明）を数えないようにするため。
   */
  function analyticsCode(): string {
    return env.TEST_ANALYTICS_SOURCE.replaceAll(/\/\*[\s\S]*?\*\//gu, '').replaceAll(
      /^\s*\/\/.*$/gmu,
      '',
    )
  }

  it('SQL 側の判定と TS 側の判定が同じ行に同じ指標を返す', async () => {
    // `eventBreakdowns` は全 kind をまとめて引いてから TS 側で畳むため、指標の
    // 判定を TS 側でも行う。SQL（METRIC_EXPR）と TS（metricOf）が別々に育つと、
    // 述語を足したときに片方だけ直る。列の組み合わせを総当たりで固定する。
    const kinds = ['visit', 'download', 'update_check', 'github_fallback', 'legacy_redirect']
    const sources = [null, 'lp', 'sparkle', 'archive']
    const pages = [null, '/', '/features']

    for (const kind of kinds) {
      for (const source of sources) {
        for (const page of pages) {
          await env.DB.prepare(
            'INSERT INTO events (timestamp, kind, source, page) VALUES (?, ?, ?, ?)',
          )
            .bind(NOW, kind, source, page)
            .run()
        }
      }
    }

    const { results } = await env.DB.prepare(
      `SELECT kind, source, page, ${METRIC_EXPR} AS metric FROM events`,
    ).all<{ kind: string; source: string | null; page: string | null; metric: string | null }>()

    expect(results).toHaveLength(kinds.length * sources.length * pages.length)
    for (const row of results) {
      expect({ ...row, metric: metricOf(row) }).toEqual(row)
    }
  })

  it('指標の述語を METRIC_FILTERS の外に書く箇所が無い', () => {
    const code = analyticsCode()

    // TS 側で kind をリテラルと比べる箇所は無い（行の判定は metricOf 経由）。
    // `METRIC_FILTERS` を読む行は定義元からの導出なので数えない。
    const handWritten = code
      .split('\n')
      .filter((line) => /kind\s*[!=]==\s*'/u.test(line) && !line.includes('METRIC_FILTERS'))
    expect(handWritten).toEqual([])

    // SQL へ kind の条件を書くのは metricExpression（`kind = '${kind}'`）と、
    // 下の意図的な例外だけ。
    // 除外してよいもの: UNIQUE_SOURCE_FILTERS の 3 行。あちらは指標（延べ件数）
    // ではなく母集団（異なり数）の述語で、範囲がたまたま一致しているだけの別物。
    // `METRIC_FILTERS.visit` に page 条件が戻っても母集団はサイト全体のままで
    // なければならないので、導出させない（analytics/sources.ts の doc を参照）。
    expect(code.match(/kind = '/gu)).toHaveLength(4)
  })
})

describe('visit の内訳（ページ別・言語別）', () => {
  /** visit を 1 件、ページ・言語・UA を指定して記録する。 */
  async function insertVisitRow(
    page: string | null,
    displayLang: string | null,
    browserLang: string | null,
    uaSummary: string | null = null,
  ): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, page, display_lang, browser_lang, ua_summary)' +
        ' VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(NOW, 'visit', page, displayLang, browserLang, uaSummary)
      .run()
  }

  it('ページ別・表示言語別・ブラウザ言語設定別を人間とロボットに分ける', async () => {
    await insertVisitRow('/', 'ja', 'ja')
    await insertVisitRow('/', 'ja', 'en')
    await insertVisitRow('/en', 'en', 'en')
    await insertVisitRow('/features', 'ja', 'ja', 'bot:GPTBot')

    const { visits } = await eventBreakdowns(env.DB)
    const { byPage, byDisplayLang, byBrowserLang } = visits

    expect(byPage).toEqual([
      { label: '/', human: 2, nonHuman: 0 },
      { label: '/en', human: 1, nonHuman: 0 },
      { label: '/features', human: 0, nonHuman: 1 },
    ])
    expect(byDisplayLang).toEqual([
      { label: 'ja', human: 2, nonHuman: 1 },
      { label: 'en', human: 1, nonHuman: 0 },
    ])
    expect(byBrowserLang).toEqual([
      { label: 'en', human: 2, nonHuman: 0 },
      { label: 'ja', human: 1, nonHuman: 1 },
    ])
  })

  it('visit 以外の kind は内訳に入らない', async () => {
    // download / update_check には page も表示言語も無い。COALESCE(page,'/') が
    // kind の条件から外れると、これらが '/' の訪問として数えられてしまう。
    await env.DB.prepare('INSERT INTO events (timestamp, kind) VALUES (?, ?)')
      .bind(NOW, 'download')
      .run()
    await env.DB.prepare('INSERT INTO events (timestamp, kind) VALUES (?, ?)')
      .bind(NOW, 'update_check')
      .run()

    const { byPage } = (await eventBreakdowns(env.DB)).visits

    expect(byPage).toEqual([])
  })

  it('列の導入前に記録された行は page は / に、言語は未記録に寄せる', async () => {
    // page は当時 LP しか計上していなかったので '/' と読んでよい。言語は
    // 日英を同一 HTML で出していた時期の行で、表示言語が確定しない。
    await insertVisitRow(null, null, null)

    const { visits } = await eventBreakdowns(env.DB)
    const { byPage, byDisplayLang, byBrowserLang } = visits

    expect(byPage).toEqual([{ label: '/', human: 1, nonHuman: 0 }])
    expect(byDisplayLang).toEqual([{ label: UNRECORDED_LABEL, human: 1, nonHuman: 0 }])
    expect(byBrowserLang).toEqual([{ label: UNRECORDED_LABEL, human: 1, nonHuman: 0 }])
  })

  it('イベントが無ければ空の内訳を返す', async () => {
    const { visits } = await eventBreakdowns(env.DB)
    const { byPage, byDisplayLang, byBrowserLang } = visits

    expect(byPage).toEqual([])
    expect(byDisplayLang).toEqual([])
    expect(byBrowserLang).toEqual([])
  })
})

describe('最新イベントと SSE の差分配信', () => {
  it('初期表示と SSE が同じ列を返す（page を含む）', async () => {
    // 2 つは同じ RecentEvent を返す契約だが、.all<RecentEvent>() のジェネリクスは
    // 実際の列を検査しない。片方から列が落ちても型では気づけないので、
    // 両方の戻り値のキー集合が一致することを固定する。
    await env.DB.prepare(
      "INSERT INTO events (timestamp, kind, page, ua_summary) VALUES (?, 'visit', '/features', 'Safari')",
    )
      .bind(NOW)
      .run()

    const [recent, streamed] = await Promise.all([recentEvents(env.DB), eventsAfter(env.DB, 0)])

    expect(recent).toHaveLength(1)
    expect(streamed).toHaveLength(1)
    expect(Object.keys(recent[0] ?? {}).toSorted()).toEqual(
      Object.keys(streamed[0] ?? {}).toSorted(),
    )
    expect(recent[0]?.page).toBe('/features')
    expect(streamed[0]?.page).toBe('/features')
  })
})

describe('イベント面のページ送り', () => {
  /**
   * visit を count 件入れる。
   *
   * 1 件ずつ INSERT すると 250 往復になるのでまとめて入れる。値はテストが決めた
   * 数値と固定文字列だけなので、バインドせず直接埋める（バインド変数には
   * 上限があり、100 件を超えた時点で `too many SQL variables` で落ちる）。
   * 1 文あたりの行数も上限があるため 50 行ずつに切る。
   */
  async function insertMany(count: number, uaSummary: string | null = null): Promise<void> {
    const ua = uaSummary === null ? 'NULL' : `'${uaSummary}'`
    const rows = Array.from(
      { length: count },
      (_unused, index) => `(${NOW + index}, 'visit', ${ua})`,
    )

    for (let start = 0; start < rows.length; start += 50) {
      const values = rows.slice(start, start + 50).join(', ')
      // 1 文ずつ順に流す（並行にしても速くならず、id の並びだけが読みにくくなる）。
      await env.DB.prepare(
        `INSERT INTO events (timestamp, kind, ua_summary) VALUES ${values}`,
      ).run()
    }
  }

  /** 先頭から「古い側」へ全ページを辿り、出てきた id を順に集める。 */
  async function walkAllPages(): Promise<number[]> {
    const seen: number[] = []
    let page = await eventPage(env.DB)

    // ページ数は有限（全件 / 100）。取りこぼしがあってもここでは止めず、
    // 集めた結果の突き合わせで落とす。
    while (true) {
      seen.push(...page.events.map((event) => event.id))
      if (page.olderCursor === undefined) break
      page = await eventPage(env.DB, { direction: 'older', id: page.olderCursor })
    }

    return seen
  }

  it('0 件のときは空のページを返し、前にも後にも送れない', async () => {
    const page = await eventPage(env.DB)

    expect(page.events).toEqual([])
    expect(page.olderCursor).toBeUndefined()
    expect(page.newerCursor).toBeUndefined()
  })

  it('先頭ページは新しい順に上限ちょうどを返し、新しい側へは送れない', async () => {
    await insertMany(EVENTS_PAGE_LIMIT + 5)

    const page = await eventPage(env.DB)
    const ids = page.events.map((event) => event.id)

    expect(page.events).toHaveLength(EVENTS_PAGE_LIMIT)
    expect(ids).toEqual([...ids].toSorted((a, b) => b - a))
    expect(page.newerCursor).toBeUndefined()
    expect(page.olderCursor).toBe(ids.at(-1))
  })

  it('最終ページでは古い側へ送れなくなる（端数のページも返る）', async () => {
    await insertMany(EVENTS_PAGE_LIMIT + 5)

    const first = await eventPage(env.DB)
    const last = await eventPage(env.DB, { direction: 'older', id: first.olderCursor ?? 0 })

    expect(last.events).toHaveLength(5)
    expect(last.olderCursor).toBeUndefined()
    expect(last.newerCursor).toBe(last.events[0]?.id)
  })

  it('先頭から最終ページまで辿ると全件を重複なく過不足なく通る', async () => {
    const total = EVENTS_PAGE_LIMIT * 2 + 37
    await insertMany(total)

    const seen = await walkAllPages()

    expect(seen).toHaveLength(total)
    expect(new Set(seen).size).toBe(total)
    // 通った id が、DB にある人間の行そのものと一致する（新しい順のまま）。
    const { results } = await env.DB.prepare('SELECT id FROM events ORDER BY id DESC').all<{
      id: number
    }>()
    expect(seen).toEqual(results.map((row) => row.id))
  })

  it('ページを送っている途中に新着が入っても、境界がずれない', async () => {
    // OFFSET で数えていると、先頭に 1 件挿さった時点で 2 ページ目の先頭が
    // 1 ページ目の末尾と重複する。カーソルが id なので重複も欠落も起きない。
    await insertMany(EVENTS_PAGE_LIMIT * 2)

    const first = await eventPage(env.DB)
    await insertMany(3)
    const second = await eventPage(env.DB, { direction: 'older', id: first.olderCursor ?? 0 })

    const firstIds = first.events.map((event) => event.id)
    const secondIds = second.events.map((event) => event.id)

    expect(secondIds).toHaveLength(EVENTS_PAGE_LIMIT)
    expect(secondIds.filter((id) => firstIds.includes(id))).toEqual([])
    expect(Math.max(...secondIds)).toBe(Math.min(...firstIds) - 1)
  })

  it('新しい側へ戻すと、送る前と同じページに戻る', async () => {
    await insertMany(EVENTS_PAGE_LIMIT * 2 + 10)

    const first = await eventPage(env.DB)
    const second = await eventPage(env.DB, { direction: 'older', id: first.olderCursor ?? 0 })
    const back = await eventPage(env.DB, { direction: 'newer', id: second.newerCursor ?? 0 })

    expect(back.events.map((event) => event.id)).toEqual(first.events.map((event) => event.id))
    expect(back.newerCursor).toBeUndefined()
  })

  it('ロボットの行は集計と同じ条件で除かれる', async () => {
    await insertMany(2, 'bot:GPTBot')
    await insertMany(1, 'Safari')

    const page = await eventPage(env.DB)

    expect(page.events).toHaveLength(1)
  })

  it('クエリの読み取りは不正な値を最新のページへ倒す', () => {
    expect(parseEventCursor({})).toBeUndefined()
    expect(parseEventCursor({ before: '120' })).toEqual({ direction: 'older', id: 120 })
    expect(parseEventCursor({ after: '120' })).toEqual({ direction: 'newer', id: 120 })
    // 両方来たら before を採る（片方を静かに無視しない）。
    expect(parseEventCursor({ before: '120', after: '9' })).toEqual({
      direction: 'older',
      id: 120,
    })
    expect(parseEventCursor({ before: '12abc' })).toBeUndefined()
    expect(parseEventCursor({ before: '-1' })).toBeUndefined()
    expect(parseEventCursor({ after: '' })).toBeUndefined()
  })
})

describe('配信面の窓と日次推移', () => {
  /** ホスト・経路・UA・時刻を指定して 1 件記録する。 */
  async function insertRoute(options: {
    ts: number
    kind: string
    host?: string | null
    fallback?: string | null
    uaSummary?: string | null
  }): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, host, fallback, ua_summary) VALUES (?, ?, ?, ?, ?)',
    )
      .bind(
        options.ts,
        options.kind,
        options.host ?? null,
        options.fallback ?? null,
        options.uaSummary ?? null,
      )
      .run()
  }

  it('窓の外の発生は「直近」に入らないが累計には残る', async () => {
    // ここが効かないと、クローラが一度舐めた跡がいつまでも「まだ落ちている」と
    // 読める（実測 2026-09-04: フォールバック 266 件のうち 262 件が 8/19-8/26 の
    // ボット由来だった）。
    await insertRoute({ ts: NOW, kind: 'github_fallback', fallback: 'dmg' })
    await insertRoute({
      ts: NOW - DAY_MS * DELIVERY_WINDOW_DAYS,
      kind: 'github_fallback',
      fallback: 'dmg',
    })

    const summary = await summarizeDelivery(env.DB, NOW)
    const route = summary.fallbacks.find((entry) => entry.label === 'dmg')

    expect(route?.human).toBe(2)
    expect(route?.humanRecent).toBe(1)
  })

  it('短いほうの窓は長いほうの部分集合として数える', async () => {
    await insertRoute({ ts: NOW, kind: 'github_fallback', fallback: 'dmg' })
    await insertRoute({
      ts: NOW - DAY_MS * DELIVERY_RECENT_DAYS,
      kind: 'github_fallback',
      fallback: 'dmg',
    })

    const summary = await summarizeDelivery(env.DB, NOW)
    const route = summary.fallbacks.find((entry) => entry.label === 'dmg')

    expect(route?.humanRecent).toBe(2)
    expect(route?.humanLatest).toBe(1)
  })

  it('日次推移は旧ホストとフォールバックを別の系列で、窓ぶんをゼロ埋めして返す', async () => {
    await insertRoute({ ts: NOW, kind: 'update_check', host: LEGACY_HOST })
    await insertRoute({ ts: NOW, kind: 'visit', host: LEGACY_HOST, uaSummary: 'bot:Googlebot' })
    await insertRoute({ ts: NOW, kind: 'github_fallback', host: CANONICAL_HOST, fallback: 'dmg' })

    const summary = await summarizeDelivery(env.DB, NOW)
    const today = summary.dailyRoutes.at(-1)

    expect(summary.dailyRoutes).toHaveLength(DELIVERY_WINDOW_DAYS)
    expect(today).toEqual({
      day: jstDayKey(NOW),
      legacyHuman: 1,
      legacyBot: 1,
      fallbackHuman: 1,
      fallbackBot: 0,
    })
  })

  it('旧ホストで落ちたフォールバックは両方の系列に入る', async () => {
    // 経路を排他に振り分けると、旧ホスト側かフォールバック側のどちらかから
    // 消える。どちらの停止判断にも要る 1 件なので両方へ足す。
    await insertRoute({ ts: NOW, kind: 'github_fallback', host: LEGACY_HOST, fallback: 'dmg' })

    const summary = await summarizeDelivery(env.DB, NOW)
    const today = summary.dailyRoutes.at(-1)

    expect(today?.legacyHuman).toBe(1)
    expect(today?.fallbackHuman).toBe(1)
  })

  it('正規ホストへのアクセスは日次推移に出ない', async () => {
    await insertRoute({ ts: NOW, kind: 'visit', host: CANONICAL_HOST })

    const summary = await summarizeDelivery(env.DB, NOW)

    expect(summary.dailyRoutes.every((point) => point.legacyHuman + point.legacyBot === 0)).toBe(
      true,
    )
  })
})

describe('リクエスト先ホストと GitHub フォールバックの内訳', () => {
  /** ホストと UA を指定して 1 件記録する。 */
  async function insertHostRow(
    kind: string,
    host: string | null,
    uaSummary: string | null = null,
  ): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, host, ua_summary) VALUES (?, ?, ?, ?)',
    )
      .bind(NOW, kind, host, uaSummary)
      .run()
  }

  it('ホスト別を kind によらず人間とロボットに分ける', async () => {
    await insertHostRow('visit', CANONICAL_HOST)
    await insertHostRow('update_check', LEGACY_HOST)
    await insertHostRow('legacy_redirect', LEGACY_HOST, 'bot:GPTBot')

    const { byHost } = await eventBreakdowns(env.DB)
    const byLabel = new Map(byHost.map((split) => [split.label, split]))

    expect(byLabel.get(CANONICAL_HOST)).toEqual({
      label: CANONICAL_HOST,
      human: 1,
      nonHuman: 0,
      lastSeenHumanAt: NOW,
      lastSeenBotAt: null,
    })
    expect(byLabel.get(LEGACY_HOST)).toEqual({
      label: LEGACY_HOST,
      human: 1,
      nonHuman: 1,
      lastSeenHumanAt: NOW,
      lastSeenBotAt: NOW,
    })
  })

  it('0 件の既知ホストも行として残る', async () => {
    // ADR 0007 の停止条件は「旧ホストを叩くクライアントがゼロ」の確認そのもの。
    // 0 の行を落とすと「まだ 0」と「そもそも計測していない」が区別できなくなる。
    await insertHostRow('visit', CANONICAL_HOST)

    const { byHost } = await eventBreakdowns(env.DB)

    for (const host of RECORDED_HOSTS) {
      expect(byHost.map((split) => split.label)).toContain(host)
    }
    // 最終発生は 0 ではなく null。0 を入れると画面が 1970 年を描き、
    // 「一度も来ていない」が「大昔に来た」に化ける。
    expect(byHost.find((split) => split.label === LEGACY_HOST)).toEqual({
      label: LEGACY_HOST,
      human: 0,
      nonHuman: 0,
      lastSeenHumanAt: null,
      lastSeenBotAt: null,
    })
  })

  it('列の導入前に記録された行は既知ホストに混ぜない', async () => {
    await insertHostRow('visit', null)

    const { byHost } = await eventBreakdowns(env.DB)

    expect(byHost.find((split) => split.label === UNRECORDED_LABEL)).toEqual({
      label: UNRECORDED_LABEL,
      human: 1,
      nonHuman: 0,
      lastSeenHumanAt: NOW,
      lastSeenBotAt: null,
    })
    expect(byHost.find((split) => split.label === CANONICAL_HOST)?.human).toBe(0)
  })

  it('GitHub フォールバックを経路別に数える', async () => {
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW, 'github_fallback', CANONICAL_HOST, 'appcast')
      .run()
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW, 'github_fallback', CANONICAL_HOST, 'dmg')
      .run()
    await insertHostRow('download', CANONICAL_HOST)

    const { byFallback } = await eventBreakdowns(env.DB)

    // fallback を持たない行は入らない（download が経路として数えられない）。
    expect(byFallback).toEqual([
      { label: 'appcast', human: 1, nonHuman: 0, lastSeenHumanAt: NOW, lastSeenBotAt: null },
      { label: 'dmg', human: 1, nonHuman: 0, lastSeenHumanAt: NOW, lastSeenBotAt: null },
    ])
  })

  it('経路ごとに最後に発生した時刻を返す', async () => {
    // 累計だけでは「直近は落ちていない」が読めない（TASK-495 の AC #4）。
    // 古い行のほうを後から入れて、順序ではなく MAX で決まっていることを見る。
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW, 'github_fallback', CANONICAL_HOST, 'dmg')
      .run()
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW - DAY_MS * 30, 'github_fallback', CANONICAL_HOST, 'dmg')
      .run()

    const { byFallback } = await eventBreakdowns(env.DB)

    expect(byFallback).toEqual([
      { label: 'dmg', human: 2, nonHuman: 0, lastSeenHumanAt: NOW, lastSeenBotAt: null },
    ])
  })

  it('最後に発生した時刻を人間とロボットで分ける', async () => {
    // 停止条件は人間が来なくなったかで決まる。混ぜた最終発生はロボットが作り続ける
    // （実測 2026-09-04: 旧ホストの直近の発生は Googlebot と Meta-ExternalAgent で、
    // Sparkle は 08-21 が最後だった）。
    await insertHostRow('update_check', LEGACY_HOST, 'Sparkle')
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, host, ua_summary) VALUES (?, ?, ?, ?)',
    )
      .bind(NOW + DAY_MS, 'visit', LEGACY_HOST, 'bot:Googlebot')
      .run()

    const { byHost } = await eventBreakdowns(env.DB)

    expect(byHost.find((split) => split.label === LEGACY_HOST)).toEqual({
      label: LEGACY_HOST,
      human: 1,
      nonHuman: 1,
      lastSeenHumanAt: NOW,
      lastSeenBotAt: NOW + DAY_MS,
    })
  })

  it('不正なリクエストと R2 の欠落を別の経路として数える', async () => {
    // 同じ 302 でも原因も対処も違う。混ぜると「配布の穴」がパス探索で水増しされる。
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW, 'github_fallback', CANONICAL_HOST, 'dmg-invalid')
      .run()
    await env.DB.prepare('INSERT INTO events (timestamp, kind, host, fallback) VALUES (?, ?, ?, ?)')
      .bind(NOW, 'github_fallback', CANONICAL_HOST, 'dmg')
      .run()

    const { byFallback } = await eventBreakdowns(env.DB)

    expect(byFallback.map((split) => split.label)).toEqual(['dmg', 'dmg-invalid'])
  })
})
