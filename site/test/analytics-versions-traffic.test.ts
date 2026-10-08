import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'

import {
  cumulativeTotals,
  dailySeries,
  hourlyDistribution,
  todayTotals,
  trafficSplit,
  UNRECORDED_LABEL,
  RUNNING_VERSION_TABLE_LABELS,
  TOP_N,
  VERSION_BREAKDOWN_METRICS,
} from '../src/analytics'
import { JST_DAY_EXPR, jstDayKey, jstDayStart, jstWindowStart } from '../src/lib/jst'
import { DATACENTER_ORG_PATTERNS, datacenterOrgMatch, isDatacenterOrg } from '../src/lib/network'
import type { EventKind } from '../src/schema'
import { clearEvents, insert, insertUpdateCheck, jst, NOW, summarizeAll } from './analytics-helpers'

afterEach(clearEvents)

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
    // 接続元組織の判定を analytics/ に手書きしない（定義元は lib/network.ts）。
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
