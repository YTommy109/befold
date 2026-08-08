import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  summarize,
  todayTotals,
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
  visitorDay: string | null = 'visitor-a',
  uaSummary: string | null = null,
): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (ts, kind, visitor_day, ua_summary) VALUES (?, ?, ?, ?)',
  )
    .bind(ts, kind, visitorDay, uaSummary)
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
      `SELECT ts, ${JST_DAY_EXPR} AS day FROM events ORDER BY ts`,
    ).all<{ ts: number; day: string }>()

    expect(results).toHaveLength(samples.length)
    for (const row of results) {
      expect(row.day).toBe(jstDayKey(row.ts))
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
    // 同一訪問者でも日が違えば visitor_day は別ハッシュになる（延べ 3）。
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
    await insert(jst('2026-08-08 10:00'), 'visit', 'visitor-a', 'ClaudeBot')
    await insert(jst('2026-08-07 10:00'), 'download', 'visitor-b', 'Safari')

    const summary = await summarize(env.DB, NOW)

    expect(summary.windowDays).toBe(14)
    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.cumulative.visitorDays).toBe(2)
    expect(summary.today.counts.visit).toBe(1)
    expect(summary.today.uniqueVisitors).toBe(1)
    expect(summary.daily).toHaveLength(14)
    expect(summary.hourly).toHaveLength(24)
    expect(summary.byUA).toEqual(
      expect.arrayContaining([
        { label: 'ClaudeBot', count: 1 },
        { label: 'Safari', count: 1 },
      ]),
    )
  })
})
