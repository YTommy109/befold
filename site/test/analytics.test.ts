import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  summarize,
  todayTotals,
  uaSplit,
} from '../src/analytics'
import { JST_DAY_EXPR, jstDayKey, jstDayStart, jstWindowStart } from '../src/lib/jst'
import type { EventKind } from '../src/schema'

/** JST 2026-08-08 12:00（= UTC 03:00）を「現在」とする固定基準。 */
const NOW = Date.parse('2026-08-08T03:00:00Z')

/** JST の 'YYYY-MM-DD HH:mm' を epoch ms にする（テストの意図を JST で書くため）。 */
function jst(text: string): number {
  return Date.parse(`${text.replace(' ', 'T')}:00+09:00`)
}

async function insert(
  ts: number,
  kind: EventKind,
  visitorToken: string | null = 'visitor-a',
  uaSummary: string | null = null,
): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, visitor_token, ua_summary) VALUES (?, ?, ?, ?)',
  )
    .bind(ts, kind, visitorToken, uaSummary)
    .run()
}

afterEach(async () => {
  await env.DB.prepare('DELETE FROM events').run()
})

describe('JST バケットの基準', () => {
  it('TS 側の日付計算と SQL 側のバケット式が同じ日を指す', async () => {
    // 2 実装（jstDayKey と JST_DAY_EXPR）が別々に JST の日を決めるため、
    // ズレても各々は正常に動いてしまう。実 SQLite と突き合わせて固定する。
    const samples = [
      jst('2026-08-08 00:00'),
      jst('2026-08-08 08:59'),
      jst('2026-08-08 23:59'),
      jst('2026-01-01 00:00'),
      jst('2026-12-31 23:59'),
    ]

    for (const ts of samples) {
      await insert(ts, 'visit')
    }

    const { results } = await env.DB.prepare(
      `SELECT timestamp, ${JST_DAY_EXPR} AS day FROM events ORDER BY timestamp`,
    ).all<{ timestamp: number; day: string }>()

    expect(results).toHaveLength(samples.length)
    for (const row of results) {
      expect(row.day).toBe(jstDayKey(row.timestamp))
    }
  })

  it('JST の 0 時をまたぐと日付が変わる（UTC 基準ではない）', () => {
    // UTC 基準なら 2026-08-07 のままになる時刻。
    expect(jstDayKey(Date.parse('2026-08-07T15:00:00Z'))).toBe('2026-08-08')
    expect(jstDayKey(Date.parse('2026-08-07T14:59:59Z'))).toBe('2026-08-07')
  })

  it('窓の開始が JST の日境界にそろう', () => {
    expect(jstDayStart(NOW)).toBe(jst('2026-08-08 00:00'))
    // 当日を含む 14 日なので、開始は 13 日前の 0 時。
    expect(jstWindowStart(NOW, 14)).toBe(jst('2026-07-26 00:00'))
  })
})

describe('todayTotals', () => {
  it('JST 当日ぶんだけを数え、前日の分を含めない', async () => {
    await insert(jst('2026-08-07 23:59'), 'visit', 'visitor-yesterday')
    await insert(jst('2026-08-08 00:00'), 'visit', 'visitor-a')
    await insert(jst('2026-08-08 11:00'), 'download', 'visitor-a')

    const today = await todayTotals(env.DB, NOW)

    expect(today.counts.visit).toBe(1)
    expect(today.counts.download).toBe(1)
    expect(today.uniqueVisitors).toBe(1)
  })

  it('日次ユニークが全期間の延べ数にならない', async () => {
    // 同一訪問者でも日が違えば visitor_token は別ハッシュになる（延べ 3）。
    await insert(jst('2026-08-06 10:00'), 'visit', 'hash-0806')
    await insert(jst('2026-08-07 10:00'), 'visit', 'hash-0807')
    await insert(jst('2026-08-08 10:00'), 'visit', 'hash-0808')

    const cumulative = await cumulativeTotals(env.DB)
    const today = await todayTotals(env.DB, NOW)

    expect(cumulative.visitorDays).toBe(3)
    expect(today.uniqueVisitors).toBe(1)
  })
})

describe('dailySeries', () => {
  it('当日を含む N 日を返し、データが無い日を 0 で埋める', async () => {
    await insert(jst('2026-08-08 10:00'), 'download')

    const daily = await dailySeries(env.DB, NOW, 14)

    expect(daily).toHaveLength(14)
    expect(daily[0]?.day).toBe('2026-07-26')
    expect(daily.at(-1)?.day).toBe('2026-08-08')
    expect(daily.at(-1)?.counts.download).toBe(1)
    expect(daily[0]?.counts.download).toBe(0)
  })

  it('窓の端（開始日の 0 時とその 1 分前）で含む・含まないが切り替わる', async () => {
    await insert(jst('2026-07-25 23:59'), 'visit', 'before-window')
    await insert(jst('2026-07-26 00:00'), 'visit', 'first-in-window')

    const daily = await dailySeries(env.DB, NOW, 14)
    const total = daily.reduce((sum, point) => sum + point.counts.visit, 0)

    expect(total).toBe(1)
    expect(daily[0]?.counts.visit).toBe(1)
  })

  it('日をまたぐイベントが JST の日付でバケットされる', async () => {
    // UTC では 2026-08-06 だが JST では 2026-08-07。
    await insert(Date.parse('2026-08-06T15:30:00Z'), 'visit')

    const daily = await dailySeries(env.DB, NOW, 14)
    const buckets = daily.filter((point) => point.counts.visit > 0).map((point) => point.day)

    expect(buckets).toEqual(['2026-08-07'])
  })
})

describe('hourlyDistribution', () => {
  it('0〜23 時がすべてそろい、JST の時刻でバケットされる', async () => {
    // UTC 15:30 = JST 翌 00:30 → hour 0 に入る。
    await insert(Date.parse('2026-08-06T15:30:00Z'), 'visit')
    await insert(jst('2026-08-08 09:10'), 'visit')

    const hourly = await hourlyDistribution(env.DB, NOW, 14)

    expect(hourly).toHaveLength(24)
    expect(hourly.map((point) => point.hour)).toEqual(Array.from({ length: 24 }, (_, i) => i))
    expect(hourly[0]?.counts.visit).toBe(1)
    expect(hourly[9]?.counts.visit).toBe(1)
    expect(hourly[12]?.counts.visit).toBe(0)
  })

  it('窓の外のイベントを含めない', async () => {
    await insert(jst('2026-07-25 09:00'), 'visit')

    const hourly = await hourlyDistribution(env.DB, NOW, 14)

    expect(hourly[9]?.counts.visit).toBe(0)
  })
})

describe('summarize', () => {
  it('累計・当日・日別・時間帯・UA 内訳をまとめて返す', async () => {
    // ロボットの巡回は集計から外れるが、専用セクション（ua）では数える。
    await insert(jst('2026-08-08 10:00'), 'visit', 'visitor-a', 'bot:ClaudeBot')
    await insert(jst('2026-08-08 10:01'), 'visit', 'visitor-c', 'Chrome')
    await insert(jst('2026-08-07 10:00'), 'download', 'visitor-b', 'Safari')

    const summary = await summarize(env.DB, NOW)

    expect(summary.windowDays).toBe(14)
    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.cumulative.visitorDays).toBe(2)
    expect(summary.today.counts.visit).toBe(1)
    expect(summary.today.uniqueVisitors).toBe(1)
    expect(summary.daily).toHaveLength(14)
    expect(summary.hourly).toHaveLength(24)
    expect(summary.ua.byBot).toEqual([{ label: 'bot:ClaudeBot', count: 1 }])
    expect(summary.ua.byHuman).toEqual([
      { label: 'Chrome', count: 1 },
      { label: 'Safari', count: 1 },
    ])
  })
})

describe('人間の訪問とロボットの巡回の分離', () => {
  it('ua_summary の bot: 接頭辞で分離し、ロボットは種類別に数える', async () => {
    await insert(jst('2026-08-08 10:00'), 'visit', 'visitor-a', 'bot:GPTBot')
    await insert(jst('2026-08-08 10:01'), 'visit', 'visitor-b', 'bot:GPTBot')
    await insert(jst('2026-08-08 10:02'), 'visit', 'visitor-c', 'bot:Googlebot')
    await insert(jst('2026-08-08 10:03'), 'visit', 'visitor-d', 'bot:other')
    await insert(jst('2026-08-08 10:04'), 'visit', 'visitor-e', 'Safari')
    // 分類の適用前に記録された行。ボットも人間も 'other' に丸まっている。
    await insert(jst('2026-08-01 10:00'), 'visit', 'visitor-f', 'other')
    // ua_summary が NULL の行（UA ヘッダ無し）はどちらにも数えない。
    await insert(jst('2026-08-08 10:05'), 'visit', 'visitor-g', null)

    const split = await uaSplit(env.DB)

    expect(split.bot).toBe(4)
    expect(split.human).toBe(2)
    expect(split.byBot).toEqual([
      { label: 'bot:GPTBot', count: 2 },
      { label: 'bot:Googlebot', count: 1 },
      { label: 'bot:other', count: 1 },
    ])
    expect(split.byHuman).toEqual([
      { label: 'Safari', count: 1 },
      { label: 'other', count: 1 },
    ])
  })

  it('データが無ければ 0 件と空の内訳を返す', async () => {
    expect(await uaSplit(env.DB)).toEqual({ human: 0, bot: 0, byHuman: [], byBot: [] })
  })
})

describe('集計からのロボット除外', () => {
  /** 内訳のカラムまで埋めて 1 件記録する（ボット／人間を ua_summary で分ける）。 */
  async function insertFull(
    ts: number,
    kind: EventKind,
    uaSummary: string | null,
    fields: { country: string; os: string; referrer: string; asOrg: string; visitor: string },
  ): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, version, country, os, ua_summary, visitor_token, referrer, as_org, source)' +
        " VALUES (?, ?, 'v1.0.0', ?, ?, ?, ?, ?, ?, 'lp')",
    )
      .bind(
        ts,
        kind,
        fields.country,
        fields.os,
        uaSummary,
        fields.visitor,
        fields.referrer,
        fields.asOrg,
      )
      .run()
  }

  const BOT = {
    country: 'US',
    os: 'Linux',
    referrer: 'https://bot.example',
    asOrg: 'BotCloud',
    visitor: 'visitor-bot',
  }
  const HUMAN = {
    country: 'JP',
    os: 'macOS 14.0',
    referrer: 'https://human.example',
    asOrg: 'HumanNet',
    visitor: 'visitor-human',
  }

  it('日次推移・国別・参照元別・OS 別・ダウンロードに人間だけが現れる', async () => {
    await insertFull(jst('2026-08-08 10:00'), 'visit', 'bot:GPTBot', BOT)
    await insertFull(jst('2026-08-08 10:01'), 'download', 'bot:GPTBot', BOT)
    await insertFull(jst('2026-08-08 11:00'), 'visit', 'Safari', HUMAN)
    await insertFull(jst('2026-08-08 11:01'), 'download', 'Safari', HUMAN)

    const summary = await summarize(env.DB, NOW)
    const today = summary.daily.at(-1)

    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.cumulative.counts.download).toBe(1)
    expect(summary.cumulative.visitorDays).toBe(1)
    expect(today?.counts.visit).toBe(1)
    expect(today?.uniqueVisitors).toBe(1)
    expect(summary.today.counts.visit).toBe(1)
    expect(summary.hourly[11]?.counts.visit).toBe(1)
    expect(summary.hourly[10]?.counts.visit).toBe(0)
    expect(summary.byCountry).toEqual([{ label: 'JP', count: 2 }])
    expect(summary.byReferrer).toEqual([{ label: 'https://human.example', count: 2 }])
    expect(summary.recent.map((event) => event.country)).toEqual(['JP', 'JP'])

    const visits = summary.perKind.find((entry) => entry.kind === 'visit')
    expect(visits?.byOS).toEqual([{ label: 'macOS 14.0', count: 1 }])
    expect(visits?.byAsOrg).toEqual([{ label: 'HumanNet', count: 1 }])
  })

  it('ua_summary が NULL の行は集計から落ちない（分類の適用前に記録された行）', async () => {
    // NULL LIKE 'bot:%' は NULL を返すため、素の LIKE を WHERE に置くと
    // この行が人間でもボットでもなく黙って消える。
    await insert(jst('2026-08-08 10:00'), 'visit', 'visitor-null', null)
    await insert(jst('2026-08-08 10:01'), 'visit', 'visitor-legacy', 'other')

    const summary = await summarize(env.DB, NOW)

    expect(summary.cumulative.counts.visit).toBe(2)
    expect(summary.today.counts.visit).toBe(2)
    expect(summary.daily.at(-1)?.counts.visit).toBe(2)
  })

  it('ボット除外の条件が 1 箇所に集約されている', () => {
    // 集計クエリを増やしたときに条件を書き写す形へ戻らないための構造ガード。
    // events を読むクエリは HUMAN_ONLY を経由するか、下の意図的な除外に限る。
    const analyticsSource = env.TEST_ANALYTICS_SOURCE
    // 除外してよいもの: uaSplit / uaBreakdown（人間とロボットの両方を数えるのが
    // 目的なので BOT_MATCH を直接使う）、maxEventId（生の id を返す SSE のカーソル）。
    const exempt = ['BOT_MATCH', 'MAX(id)']
    const windows = [...analyticsSource.matchAll(/FROM events/g)].map((match) =>
      analyticsSource.slice(Math.max(0, (match.index ?? 0) - 200), (match.index ?? 0) + 400),
    )

    expect(windows).not.toHaveLength(0)
    for (const window of windows) {
      if (exempt.some((marker) => window.includes(marker))) continue
      expect(window).toContain('${HUMAN_ONLY}')
    }

    // 条件そのものは 1 箇所だけで定義される。
    expect(analyticsSource.match(/LIKE '\$\{BOT_PREFIX\}%'/g)).toHaveLength(1)
  })
})

describe('ダウンロード経路の分離', () => {
  /** source を明示して 1 件記録する。source=null は列の導入前に記録された行。 */
  async function insertDownload(source: string | null, version: string): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, version, source) VALUES (?, ?, ?, ?)',
    )
      .bind(NOW, 'download', version, source)
      .run()
  }

  it('LP 経由と Sparkle 経由を別の指標として数える', async () => {
    await insertDownload('lp', 'v1.2.3')
    await insertDownload('sparkle', 'v1.2.3')
    await insertDownload('sparkle', 'v1.2.4')

    const totals = await cumulativeTotals(env.DB)

    expect(totals.counts.download).toBe(1)
    expect(totals.counts.update_download).toBe(2)
  })

  it('source 列の導入前に記録された行は LP 経由として数える', async () => {
    // source が NULL の行は、Worker を通るダウンロードが LP 経由しか存在
    // しなかった時期のもの。ここが崩れると過去の DL 数の系列が不連続になる。
    await insertDownload(null, 'v1.2.3')

    const totals = await cumulativeTotals(env.DB)

    expect(totals.counts.download).toBe(1)
    expect(totals.counts.update_download).toBe(0)
  })

  it('指標別の OS 内訳が LP 経由と Sparkle 経由で混ざらない', async () => {
    // 指標の判定を 1 本のクエリの CASE 式へ寄せているため、source の取り違えが
    // あっても本数は変わらず値だけが壊れる。
    await env.DB.prepare(
      "INSERT INTO events (timestamp, kind, os, as_org, source) VALUES (?, 'download', ?, ?, ?)",
    )
      .bind(NOW, 'macOS 14.0', 'HumanNet', 'lp')
      .run()
    await env.DB.prepare(
      "INSERT INTO events (timestamp, kind, os, as_org, source) VALUES (?, 'download', ?, ?, ?)",
    )
      .bind(NOW, 'macOS 15.0', 'UpdateNet', 'sparkle')
      .run()

    const summary = await summarize(env.DB, NOW)
    const lp = summary.perKind.find((entry) => entry.kind === 'download')
    const sparkle = summary.perKind.find((entry) => entry.kind === 'update_download')

    expect(lp?.byOS).toEqual([{ label: 'macOS 14.0', count: 1 }])
    expect(lp?.byAsOrg).toEqual([{ label: 'HumanNet', count: 1 }])
    expect(sparkle?.byOS).toEqual([{ label: 'macOS 15.0', count: 1 }])
    expect(sparkle?.byAsOrg).toEqual([{ label: 'UpdateNet', count: 1 }])
  })

  it('指標別の内訳は上位 10 件で打ち切られる', async () => {
    // 1 本のクエリへまとめても指標ごとに上限が効くこと（LIMIT では全体で 1 回しか
    // 効かず、行数がイベントの種類数に比例して増えてしまう）。
    for (let index = 0; index < 11; index += 1) {
      await env.DB.prepare("INSERT INTO events (timestamp, kind, os) VALUES (?, 'visit', ?)")
        .bind(NOW, `os-${index}`)
        .run()
    }

    const summary = await summarize(env.DB, NOW)

    expect(summary.perKind.find((entry) => entry.kind === 'visit')?.byOS).toHaveLength(10)
  })

  it('バージョン別内訳は LP 経由だけを対象にする', async () => {
    await insertDownload('lp', 'v1.2.3')
    await insertDownload('sparkle', 'v1.2.4')

    const summary = await summarize(env.DB, NOW)

    expect(summary.byVersion).toEqual([{ label: 'v1.2.3', count: 1 }])
  })
})
