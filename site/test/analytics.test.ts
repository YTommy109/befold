import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'

import {
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  summarizeDelivery,
  summarizeOverview,
  summarizeTraffic,
  summarizeUsers,
  todayTotals,
  eventsAfter,
  eventPage,
  parseEventCursor,
  EVENTS_PAGE_LIMIT,
  recentEvents,
  trafficSplit,
  eventBreakdowns,
  OPERATIONAL_KINDS,
  UNRECORDED_LABEL,
  KIND_LABELS,
  UNIQUE_SOURCE_LABELS,
  VERSION_BREAKDOWN_METRICS,
  RUNNING_VERSION_LABELS,
  RUNNING_VERSION_TABLE_LABELS,
  TOP_N,
} from '../src/analytics'

/**
 * 面ごとに分かれた集計をまとめて 1 つのオブジェクトにする（テスト専用）。
 *
 * ここで検証したいのは集計 SQL の振る舞いであって、どの面にどの指標が載るかでは
 * ない。面の割り当ては `test/query-count.test.ts`（本数）と
 * `test/dashboard.test.ts`（表示）が担保する。
 */
async function summarizeAll(db: D1Database, now: number) {
  const [overview, users, traffic, delivery] = await Promise.all([
    summarizeOverview(db, now),
    summarizeUsers(db, now),
    summarizeTraffic(db),
    summarizeDelivery(db),
  ])

  return { ...overview, ...users, ...traffic, ...delivery }
}
import { CANONICAL_HOST, LEGACY_HOST, RECORDED_HOSTS } from '../src/lib/hosts'
import { DAY_MS, JST_DAY_EXPR, jstDayKey, jstDayStart, jstWindowStart } from '../src/lib/jst'
import { DATACENTER_ORG_PATTERNS, datacenterOrgMatch, isDatacenterOrg } from '../src/lib/network'
import { channelSchema, downloadSourceSchema, eventKindSchema } from '../src/schema'
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

/** update_check を 1 件入れる（稼働バージョン分布のテスト用）。 */
async function insertUpdateCheck(options: {
  ts: number
  appVersion: string | null
  channel?: string | null
  visitorToken?: string
  uaSummary?: string | null
  asOrg?: string | null
}): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, channel, app_version, visitor_token, ua_summary, as_org)' +
      " VALUES (?, 'update_check', ?, ?, ?, ?, ?)",
  )
    .bind(
      options.ts,
      // `?? 'stable'` にしない。明示した null が既定値に化けて、
      // チャネル未記録のケースを検証できなくなる。
      'channel' in options ? options.channel : 'stable',
      options.appVersion,
      options.visitorToken ?? 'visitor-a',
      options.uaSummary ?? 'Sparkle',
      options.asOrg ?? null,
    )
    .run()
}

describe('稼働中のアプリバージョン', () => {
  it('延べ確認回数ではなくアクセス元の異なり数を数える', async () => {
    // 同じアクセス元から 3 回確認が来ても 1。起動回数ではなく規模を見るため。
    for (const ts of [jst('2026-08-08 01:00'), jst('2026-08-08 02:00'), jst('2026-08-08 03:00')]) {
      await insertUpdateCheck({ ts, appVersion: '1.13.1', visitorToken: 'visitor-a' })
    }
    await insertUpdateCheck({
      ts: jst('2026-08-08 04:00'),
      appVersion: '1.13.1',
      visitorToken: 'visitor-b',
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toEqual([{ label: '1.13.1', count: 2 }])
  })

  it('develop は数えない（作者の開発機しか映らない）', async () => {
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.13.1',
      channel: 'stable',
      visitorToken: 'visitor-a',
    })
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.13.2-dev.4',
      channel: 'develop',
      visitorToken: 'visitor-b',
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toEqual([{ label: '1.13.1', count: 1 }])
    expect(summary.runningVersions).not.toHaveProperty('develop')
  })

  it('チャネルが記録されていない行を落とさない', async () => {
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.12.0',
      channel: null,
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.unrecorded).toEqual([{ label: '1.12.0', count: 1 }])
  })

  it('窓の外の確認は数えない（今も使われている版だけを見る）', async () => {
    await insertUpdateCheck({
      ts: jst('2026-06-01 01:00'),
      appVersion: '1.9.0',
      visitorToken: 'visitor-old',
    })
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.13.1',
      visitorToken: 'visitor-a',
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toEqual([{ label: '1.13.1', count: 1 }])
  })

  it('バージョンを名乗らない確認は出てこない（app_version が NULL）', async () => {
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: null,
      uaSummary: 'curl',
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toEqual([])
  })

  it('ボットとデータセンターは他の集計と同じ条件で除外する', async () => {
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.13.1',
      visitorToken: 'visitor-bot',
      uaSummary: 'bot:Googlebot',
    })
    await insertUpdateCheck({
      ts: jst('2026-08-08 01:00'),
      appVersion: '1.13.1',
      visitorToken: 'visitor-dc',
      asOrg: DATACENTER_ORG_PATTERNS[0],
    })

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toEqual([])
  })

  it('0 件のチャネルも表そのものは残す（未計測と 0 件を混同させない）', async () => {
    const summary = await summarizeAll(env.DB, NOW)

    for (const { key } of RUNNING_VERSION_TABLE_LABELS) {
      expect(summary.runningVersions[key]).toEqual([])
    }
  })

  it('上位 N 件で切る', async () => {
    for (let i = 0; i < TOP_N + 3; i += 1) {
      // 件数に差を付けて順位を確定させる（同数だとラベル順に倒れて意図が読めない）。
      for (let n = 0; n <= i; n += 1) {
        await insertUpdateCheck({
          ts: jst('2026-08-08 01:00'),
          appVersion: `1.0.${i}`,
          visitorToken: `visitor-${i}-${n}`,
        })
      }
    }

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.runningVersions.stable).toHaveLength(TOP_N)
    expect(summary.runningVersions.stable[0]?.label).toBe(`1.0.${TOP_N + 2}`)
  })
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

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.windowDays).toBe(14)
    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.cumulative.visitorDays).toBe(2)
    expect(summary.today.counts.visit).toBe(1)
    expect(summary.today.uniqueVisitors).toBe(1)
    expect(summary.daily).toHaveLength(14)
    expect(summary.hourly).toHaveLength(24)
    expect(summary.traffic.breakdowns.bot).toEqual([{ label: 'bot:ClaudeBot', count: 1 }])
    expect(summary.traffic.breakdowns.human).toEqual([
      { label: 'Chrome', count: 1 },
      { label: 'Safari', count: 1 },
    ])
  })
})

describe('人間の訪問と自動アクセスの分離', () => {
  /** 接続元組織まで指定して visit を 1 件記録する。 */
  async function insertOrg(ts: number, uaSummary: string | null, asOrg: string | null) {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, visitor_token, ua_summary, as_org, page)' +
        " VALUES (?, 'visit', ?, ?, ?, '/')",
    )
      .bind(ts, `visitor-${ts}`, uaSummary, asOrg)
      .run()
  }

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

    const split = await trafficSplit(env.DB)

    expect(split.totals.bot).toBe(4)
    // ua_summary が NULL の行も人間側に数える（区分から黙って消さない）。内訳では
    // 「未記録」として出す。
    expect(split.totals.human).toBe(3)
    expect(split.totals.datacenter).toBe(0)
    expect(split.breakdowns.bot).toEqual([
      { label: 'bot:GPTBot', count: 2 },
      { label: 'bot:Googlebot', count: 1 },
      { label: 'bot:other', count: 1 },
    ])
    // 同数はラベル順。'other' < 'Safari' < '未記録'（コードポイント順）。
    expect(split.breakdowns.human).toEqual([
      { label: 'Safari', count: 1 },
      { label: 'other', count: 1 },
      { label: UNRECORDED_LABEL, count: 1 },
    ])
  })

  it('接続元組織がデータセンターなら、UA がブラウザでも人間から外す', async () => {
    // ADR 0008。UA だけを見ていた頃はこれらが「人間の訪問」に入っていた。
    await insertOrg(jst('2026-08-08 10:00'), 'Chrome', 'Amazon Data Services Northern Virginia')
    await insertOrg(jst('2026-08-08 10:01'), 'other', 'Meta Platforms Ireland Limited')
    await insertOrg(jst('2026-08-08 10:02'), 'other', 'Driftnet Ltd')
    // 消費者向け ISP は人間側に残す。
    await insertOrg(jst('2026-08-08 10:03'), 'Chrome', 'ARTERIA Networks Corp.')
    // プライバシー中継の出口は人間側に残す（iCloud Private Relay / WARP）。
    await insertOrg(jst('2026-08-08 10:04'), 'Chrome', 'Cloudflare London, LLC')
    // 接続元が分からない行も人間側に残す（NULL は「データセンターでない」ではない）。
    await insertOrg(jst('2026-08-08 10:05'), 'Chrome', null)
    // UA でボットと分かるものは、接続元がデータセンターでもロボット側で数える
    // （クローラ名の内訳を失わないため）。
    await insertOrg(jst('2026-08-08 10:06'), 'bot:GPTBot', 'Microsoft Corporation')

    const split = await trafficSplit(env.DB)

    expect(split.totals.datacenter).toBe(3)
    expect(split.totals.human).toBe(3)
    expect(split.totals.bot).toBe(1)
    // データセンター側の内訳ラベルは接続元組織（UA を出しても Chrome が並ぶだけ）。
    expect(split.breakdowns.datacenter).toEqual([
      { label: 'Amazon Data Services Northern Virginia', count: 1 },
      { label: 'Driftnet Ltd', count: 1 },
      { label: 'Meta Platforms Ireland Limited', count: 1 },
    ])
  })

  it('データセンター由来は集計全体からも外れる（全期間に遡って効く）', async () => {
    // as_org は記録済みなので、UA 分類と違って過去の行にも判定が効く。
    await insertOrg(jst('2026-08-01 10:00'), 'Chrome', 'Amazon Technologies Inc.')
    await insertOrg(jst('2026-08-08 10:00'), 'Chrome', 'ARTERIA Networks Corp.')

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.recent).toHaveLength(1)
  })

  it('データが無ければ 0 件と空の内訳を返す', async () => {
    expect(await trafficSplit(env.DB)).toEqual({
      totals: { human: 0, bot: 0, datacenter: 0 },
      breakdowns: { human: [], bot: [], datacenter: [] },
    })
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

    const summary = await summarizeAll(env.DB, NOW)
    const today = summary.daily.at(-1)

    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.cumulative.counts.download).toBe(1)
    expect(summary.cumulative.visitorDays).toBe(1)
    expect(today?.counts.visit).toBe(1)
    expect(today?.uniqueSources.visit).toBe(1)
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

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.cumulative.counts.visit).toBe(2)
    expect(summary.today.counts.visit).toBe(2)
    expect(summary.daily.at(-1)?.counts.visit).toBe(2)
  })

  it('自動アクセス除外の条件が 1 箇所に集約されている', () => {
    // 集計クエリを増やしたときに条件を書き写す形へ戻らないための構造ガード。
    // events を読むクエリは HUMAN_ONLY を経由するか、下の意図的な除外に限る。
    const analyticsSource = env.TEST_ANALYTICS_SOURCE
    // 除外してよいもの: trafficSplit（人間・ロボット・データセンターの全区分を
    // 数えるのが目的なので TRAFFIC_CLASS_EXPR を直接使う）、eventBreakdowns
    // （人間側と自動アクセス側の両方を返し TS 側で分ける）、maxEventId
    // （生の id を返す SSE のカーソル）。
    const exempt = ['TRAFFIC_CLASS_EXPR', 'TRAFFIC_LABEL_EXPR', 'NON_HUMAN_MATCH', 'MAX(id)']
    const windows = [...analyticsSource.matchAll(/FROM events/gu)].map((match) =>
      analyticsSource.slice(Math.max(0, (match.index ?? 0) - 200), (match.index ?? 0) + 400),
    )

    expect(windows).not.toHaveLength(0)
    for (const window of windows) {
      if (exempt.some((marker) => window.includes(marker))) continue
      expect(window).toContain('${HUMAN_ONLY}')
    }

    // 条件そのものは軸ごとに 1 箇所だけで定義される。
    expect(analyticsSource.match(/LIKE '\$\{BOT_PREFIX\}%'/gu)).toHaveLength(1)
    expect(analyticsSource.match(/datacenterOrgMatch\(/gu)).toHaveLength(1)
    // 接続元組織の判定を analytics.ts に手書きしない（定義元は lib/network.ts）。
    expect(analyticsSource).not.toMatch(/as_org.*LIKE '%/u)
  })

  it('接続元組織の判定は配列ひとつから生成される', () => {
    // SQL 断片を手書きすると、パターンを足したときに片方だけ直る。
    const sql = datacenterOrgMatch()
    expect(sql.match(/LIKE '%/gu)).toHaveLength(DATACENTER_ORG_PATTERNS.length)
    for (const pattern of DATACENTER_ORG_PATTERNS) {
      expect(sql).toContain(`LIKE '%${pattern}%'`)
      // SQL へそのまま埋めるため、引用符とワイルドカードは持てない。
      expect(pattern).not.toMatch(/['%_]/u)
      expect(isDatacenterOrg(`Example ${pattern} Inc.`)).toBe(true)
    }
    // NULL は「データセンターでない」ではなく「不明」。人間側に残す。
    expect(isDatacenterOrg(null)).toBe(false)
    expect(sql).toContain("COALESCE(as_org, '')")
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

    const summary = await summarizeAll(env.DB, NOW)
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

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.perKind.find((entry) => entry.kind === 'visit')?.byOS).toHaveLength(10)
  })

  it('バージョン別内訳は指標ごとに分かれる（LP と旧版配布を混ぜない）', async () => {
    await insertDownload('lp', 'v1.2.3')
    await insertDownload('sparkle', 'v1.2.4')
    await insertDownload('archive', 'v1.1.0')

    const summary = await summarizeAll(env.DB, NOW)
    const versionsOf = (kind: string) =>
      summary.perKind.find((entry) => entry.kind === kind)?.byVersion

    expect(versionsOf('download')).toEqual([{ label: 'v1.2.3', count: 1 }])
    expect(versionsOf('update_download')).toEqual([{ label: 'v1.2.4', count: 1 }])
    expect(versionsOf('archive_download')).toEqual([{ label: 'v1.1.0', count: 1 }])
  })

  it('バージョン別内訳を出すのはダウンロード系の指標だけ', () => {
    // version 列を持たない指標にまで表を出すと、常に空の表が並ぶ。
    expect([...VERSION_BREAKDOWN_METRICS].toSorted()).toEqual([
      'archive_download',
      'download',
      'update_download',
    ])
  })
})

describe('ページの分離', () => {
  /** page を明示して visit を 1 件記録する。page=null は列の導入前に記録された行。 */
  async function insertVisit(page: string | null, ts: number = NOW): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, visitor_token, page) VALUES (?, ?, ?, ?)',
    )
      .bind(ts, 'visit', `visitor-${page ?? 'legacy'}`, page)
      .run()
  }

  it('「ページアクセス」の全系列が LP だけを数える', async () => {
    // 指標の述語は METRIC_FILTERS 1 箇所から組み立てる決まりで、累計・当日・
    // 日次・時間帯・内訳がそれを共有する。どれか 1 つが述語を書き写す形へ
    // 戻ると /features がここで混ざるので、全系列をまとめて固定する。
    await insertVisit('/')
    await insertVisit('/features')
    await insertVisit('/features')

    const summary = await summarizeAll(env.DB, NOW)

    expect(summary.cumulative.counts.visit).toBe(1)
    expect(summary.today.counts.visit).toBe(1)
    expect(summary.daily.at(-1)?.counts.visit).toBe(1)
    expect(summary.hourly.reduce((total, hour) => total + hour.counts.visit, 0)).toBe(1)
    expect(summary.perKind.find((entry) => entry.kind === 'visit')?.total).toBe(1)
  })

  it('page 列の導入前に記録された visit は LP として数える', async () => {
    // 当時 visit を計上していたのは LP だけ（src/routes/public.tsx）。
    // 遡って埋め直す材料は無いので COALESCE(page, '/') でその事実を表す。
    await insertVisit(null)

    expect((await cumulativeTotals(env.DB)).counts.visit).toBe(1)
  })

  it('日次ユニーク訪問者はページで絞らない（サイト全体の訪問者数）', async () => {
    // 指標ごとの件数と違い、COUNT(DISTINCT visitor_token) は「何人来たか」を
    // 測るもの。LP だけに絞ると /features へ直接来た訪問者が数から消える。
    await insertVisit('/')
    await insertVisit('/features')

    const totals = await todayTotals(env.DB, NOW)

    expect(totals.counts.visit).toBe(1)
    expect(totals.uniqueVisitors).toBe(2)
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

    expect(byLabel.get(CANONICAL_HOST)).toEqual({ label: CANONICAL_HOST, human: 1, nonHuman: 0 })
    expect(byLabel.get(LEGACY_HOST)).toEqual({ label: LEGACY_HOST, human: 1, nonHuman: 1 })
  })

  it('0 件の既知ホストも行として残る', async () => {
    // ADR 0007 の停止条件は「旧ホストを叩くクライアントがゼロ」の確認そのもの。
    // 0 の行を落とすと「まだ 0」と「そもそも計測していない」が区別できなくなる。
    await insertHostRow('visit', CANONICAL_HOST)

    const { byHost } = await eventBreakdowns(env.DB)

    for (const host of RECORDED_HOSTS) {
      expect(byHost.map((split) => split.label)).toContain(host)
    }
    expect(byHost.find((split) => split.label === LEGACY_HOST)).toEqual({
      label: LEGACY_HOST,
      human: 0,
      nonHuman: 0,
    })
  })

  it('列の導入前に記録された行は既知ホストに混ぜない', async () => {
    await insertHostRow('visit', null)

    const { byHost } = await eventBreakdowns(env.DB)

    expect(byHost.find((split) => split.label === UNRECORDED_LABEL)).toEqual({
      label: UNRECORDED_LABEL,
      human: 1,
      nonHuman: 0,
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
      { label: 'appcast', human: 1, nonHuman: 0, lastSeenAt: NOW },
      { label: 'dmg', human: 1, nonHuman: 0, lastSeenAt: NOW },
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

    expect(byFallback).toEqual([{ label: 'dmg', human: 2, nonHuman: 0, lastSeenAt: NOW }])
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

describe('kind の行き先', () => {
  it('すべての kind が指標か運用観測のどちらかに割り当てられている', () => {
    // kind を足したときに、カード・グラフにも運用セクションにも出ないまま
    // 記録だけされる状態を防ぐ構造ガード。どちらにするかをここで必ず決めさせる。
    const shown = new Set([...KIND_LABELS.map((entry) => entry.kind), ...OPERATIONAL_KINDS])

    for (const kind of eventKindSchema.options) {
      expect(shown.has(kind)).toBe(true)
    }
    // 指標にしか出ない 'update_download' は EventKind ではない派生指標。
    expect(shown.has('update_download')).toBe(true)
  })

  it('download の source はすべてどれか 1 つの指標に数えられる', async () => {
    // source を足したのに指標系列を足さないと、その経路のダウンロードは
    // どのカード・グラフにも出ないまま記録だけされる。型では捕まらない
    // （MetricKey は EventKind から導かれ、source は関与しない）ので、
    // 「1 件入れたらどこか 1 系列だけが 1 になる」ことで縛る。
    for (const source of downloadSourceSchema.options) {
      await env.DB.prepare('INSERT INTO events (timestamp, kind, source) VALUES (?, ?, ?)')
        .bind(NOW, 'download', source)
        .run()

      const totals = await cumulativeTotals(env.DB)
      const counted = KIND_LABELS.filter((entry) => totals.counts[entry.kind] > 0)

      expect(
        counted.map((entry) => entry.kind),
        source,
      ).toHaveLength(1)

      await env.DB.prepare('DELETE FROM events').run()
    }
  })

  it('運用観測の kind はカード・グラフの系列に出ない', () => {
    for (const kind of OPERATIONAL_KINDS) {
      expect(KIND_LABELS.map((entry) => entry.kind)).not.toContain(kind)
    }
  })
})

describe('日別のユニークアクセス元', () => {
  /** アクセス元（visitor_token）とチャネルを指定して 1 件記録する。 */
  async function insertSource(
    ts: number,
    kind: EventKind,
    visitorToken: string,
    options: { channel?: string | null; page?: string | null; uaSummary?: string | null } = {},
  ): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, channel, page, visitor_token, ua_summary)' +
        ' VALUES (?, ?, ?, ?, ?, ?)',
    )
      .bind(
        ts,
        kind,
        options.channel ?? null,
        options.page ?? null,
        visitorToken,
        options.uaSummary ?? null,
      )
      .run()
  }

  const TODAY = jst('2026-08-08 10:00')

  it('サイト訪問とアプリのアップデート確認を合算しない', async () => {
    // 同じアクセス元がサイトも見てアプリも使った場合。合算すると 1 になり、
    // どちらの母集団の規模も表さない数になる。
    await insertSource(TODAY, 'visit', 'source-a', { page: '/' })
    await insertSource(TODAY, 'update_check', 'source-a', { channel: 'stable' })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.visit).toBe(1)
    expect(point?.uniqueSources.update_check_stable).toBe(1)
  })

  it('stable と develop が混ざらない', async () => {
    await insertSource(TODAY, 'update_check', 'source-a', { channel: 'stable' })
    await insertSource(TODAY, 'update_check', 'source-b', { channel: 'stable' })
    await insertSource(TODAY, 'update_check', 'source-c', { channel: 'develop' })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.update_check_stable).toBe(2)
    expect(point?.uniqueSources.update_check_develop).toBe(1)
  })

  it('チャネルが記録されていない行はどちらにも混ぜず未記録として数える', async () => {
    await insertSource(TODAY, 'update_check', 'source-a', { channel: null })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.update_check_unrecorded).toBe(1)
    expect(point?.uniqueSources.update_check_stable).toBe(0)
    expect(point?.uniqueSources.update_check_develop).toBe(0)
  })

  it('サイト訪問はページで絞らない（ページアクセスの指標とは母数が違う）', async () => {
    await insertSource(TODAY, 'visit', 'source-a', { page: '/' })
    await insertSource(TODAY, 'visit', 'source-b', { page: '/features' })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.visit).toBe(2)
    expect(point?.counts.visit).toBe(1)
  })

  it('同じアクセス元が同じ日に何度来ても 1 と数える', async () => {
    await insertSource(jst('2026-08-08 09:00'), 'update_check', 'source-a', { channel: 'stable' })
    await insertSource(jst('2026-08-08 11:00'), 'update_check', 'source-a', { channel: 'stable' })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.update_check_stable).toBe(1)
    expect(point?.counts.update_check).toBe(2)
  })

  it('ロボットは他の集計と同じ条件で除外される', async () => {
    await insertSource(TODAY, 'update_check', 'source-bot', {
      channel: 'stable',
      uaSummary: 'bot:GPTBot',
    })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.update_check_stable).toBe(0)
  })

  it('記録のない日も 0 の点として並ぶ', async () => {
    const series = await dailySeries(env.DB, NOW)

    expect(series.at(0)?.uniqueSources).toEqual({
      visit: 0,
      update_check_stable: 0,
      update_check_develop: 0,
      update_check_unrecorded: 0,
    })
  })

  it('全チャネルに系列と表示名がある', async () => {
    // チャネルを増やしたときに記録側だけが増え、集計・表示の系列が増えないと、
    // 新チャネルの数字が画面のどこにも出ないまま落ちる。
    const keys = UNIQUE_SOURCE_LABELS.map((entry) => entry.key)
    const point = (await dailySeries(env.DB, NOW)).at(-1)

    for (const channel of channelSchema.options) {
      expect(keys).toContain(`update_check_${channel}`)
    }
    expect(new Set(keys)).toEqual(new Set(Object.keys(point?.uniqueSources ?? {})))
    expect(UNIQUE_SOURCE_LABELS.every((entry) => entry.label.length > 0)).toBe(true)
  })
})

/**
 * 同日・同チャネルで sparkle 経由のダウンロードを 1 件入れる。
 *
 * 転換率の分子は「確認と更新の両方を持つアクセス元」なので、確認と同じ
 * visitor_token を渡せるようにしてある。
 */
async function insertSparkleDownload(options: {
  ts: number
  channel?: string | null
  visitorToken?: string
  version?: string
  uaSummary?: string | null
}): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO events (timestamp, kind, source, channel, version, visitor_token, ua_summary)' +
      " VALUES (?, 'download', 'sparkle', ?, ?, ?, ?)",
  )
    .bind(
      options.ts,
      'channel' in options ? options.channel : 'stable',
      options.version ?? 'v1.13.0',
      options.visitorToken ?? 'visitor-a',
      options.uaSummary ?? 'Sparkle',
    )
    .run()
}

describe('アップデートの取り込み', () => {
  it('確認と更新の両方を持つアクセス元だけを分子に数える', async () => {
    const ts = jst('2026-08-08 01:00')
    // 確認だけ（更新していない）
    await insertUpdateCheck({ ts, appVersion: '1.12.0', visitorToken: 'only-check' })
    // 確認して更新した
    await insertUpdateCheck({ ts, appVersion: '1.12.0', visitorToken: 'converted' })
    await insertSparkleDownload({ ts, visitorToken: 'converted' })

    const { conversion } = await summarizeUsers(env.DB, NOW)
    const day = conversion.stable.find((point) => point.day === '2026-08-08')

    expect(day).toMatchObject({ checked: 2, converted: 1, downloadedWithoutCheck: 0 })
  })

  it('同日に確認の記録がない更新は分子に入れず、別に数える', async () => {
    // 前日に確認して当日に落ちてきた場合や、確認と取得で UA が変わって
    // visitor_token が別になった場合にこうなる。率へ混ぜると 100% を超える。
    const ts = jst('2026-08-08 01:00')
    await insertUpdateCheck({ ts, appVersion: '1.12.0', visitorToken: 'checked' })
    await insertSparkleDownload({ ts, visitorToken: 'never-checked' })

    const { conversion } = await summarizeUsers(env.DB, NOW)
    const day = conversion.stable.find((point) => point.day === '2026-08-08')

    expect(day).toMatchObject({ checked: 1, converted: 0, downloadedWithoutCheck: 1 })
  })

  it('同じアクセス元が何度確認・更新しても 1 と数える', async () => {
    for (const at of ['2026-08-08 01:00', '2026-08-08 05:00', '2026-08-08 09:00']) {
      await insertUpdateCheck({ ts: jst(at), appVersion: '1.12.0', visitorToken: 'same' })
      await insertSparkleDownload({ ts: jst(at), visitorToken: 'same' })
    }

    const { conversion } = await summarizeUsers(env.DB, NOW)
    const day = conversion.stable.find((point) => point.day === '2026-08-08')

    expect(day).toMatchObject({ checked: 1, converted: 1 })
  })

  it('チャネルが混ざらない', async () => {
    const ts = jst('2026-08-08 01:00')
    await insertUpdateCheck({ ts, appVersion: '1.12.0', visitorToken: 'st', channel: 'stable' })
    await insertSparkleDownload({ ts, visitorToken: 'st', channel: 'stable' })
    await insertUpdateCheck({ ts, appVersion: '1.12.0', visitorToken: 'dv', channel: 'develop' })

    const { conversion } = await summarizeUsers(env.DB, NOW)

    expect(conversion.stable.find((point) => point.day === '2026-08-08')).toMatchObject({
      checked: 1,
      converted: 1,
    })
    expect(conversion.develop.find((point) => point.day === '2026-08-08')).toMatchObject({
      checked: 1,
      converted: 0,
    })
  })

  it('ロボットの確認・更新は数えない', async () => {
    const ts = jst('2026-08-08 01:00')
    await insertUpdateCheck({
      ts,
      appVersion: '1.12.0',
      visitorToken: 'bot',
      uaSummary: 'bot:GPTBot',
    })
    await insertSparkleDownload({ ts, visitorToken: 'bot', uaSummary: 'bot:GPTBot' })

    const { conversion } = await summarizeUsers(env.DB, NOW)
    const day = conversion.stable.find((point) => point.day === '2026-08-08')

    expect(day).toMatchObject({ checked: 0, converted: 0, downloadedWithoutCheck: 0 })
  })

  it('窓の外の日は含まない', async () => {
    await insertUpdateCheck({
      ts: jst('2026-07-01 01:00'),
      appVersion: '1.12.0',
      visitorToken: 'old',
    })

    const { conversion } = await summarizeUsers(env.DB, NOW)

    expect(conversion.stable.some((point) => point.day === '2026-07-01')).toBe(false)
  })

  it('データが無くてもチャネルごとの系列は消えない', async () => {
    const { conversion } = await summarizeUsers(env.DB, NOW)

    for (const { key } of RUNNING_VERSION_LABELS) expect(conversion[key]).toBeDefined()
  })

  it('タグごとの取り込みを初回観測からの経過日数で積み上げる', async () => {
    // 初回観測が 08-06、その 2 日後にもう 1 台。0 日目 1 件 → 2 日目 2 件（累積）。
    await insertSparkleDownload({
      ts: jst('2026-08-06 10:00'),
      visitorToken: 'a',
      version: 'v1.13.0',
    })
    await insertSparkleDownload({
      ts: jst('2026-08-08 10:00'),
      visitorToken: 'b',
      version: 'v1.13.0',
    })

    const { adoption } = await summarizeUsers(env.DB, NOW)
    const tag = adoption.find((entry) => entry.version === 'v1.13.0')

    expect(tag?.channel).toBe('stable')
    expect(tag?.firstSeenDay).toBe('2026-08-06')
    expect(tag?.cumulative).toEqual([
      { elapsedDays: 0, sources: 1 },
      { elapsedDays: 2, sources: 2 },
    ])
  })

  it('取り込み曲線もアクセス元の異なり数で数える', async () => {
    // 同じアクセス元が同じタグを 2 回落としても 1。
    await insertSparkleDownload({
      ts: jst('2026-08-06 10:00'),
      visitorToken: 'a',
      version: 'v1.13.0',
    })
    await insertSparkleDownload({
      ts: jst('2026-08-06 12:00'),
      visitorToken: 'a',
      version: 'v1.13.0',
    })

    const { adoption } = await summarizeUsers(env.DB, NOW)

    expect(adoption.find((entry) => entry.version === 'v1.13.0')?.cumulative).toEqual([
      { elapsedDays: 0, sources: 1 },
    ])
  })

  it('LP 経由のダウンロードは取り込みに数えない', async () => {
    // 新規獲得であって更新ではない。source で分ける。
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, source, channel, version, visitor_token, ua_summary)' +
        " VALUES (?, 'download', 'lp', 'stable', 'v1.13.0', 'lp-user', 'Safari')",
    )
      .bind(jst('2026-08-06 10:00'))
      .run()

    const { adoption } = await summarizeUsers(env.DB, NOW)

    expect(adoption).toHaveLength(0)
  })
})
