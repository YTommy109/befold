import { env } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'

import {
  cumulativeTotals,
  dailySeries,
  summarizeTraffic,
  summarizeUsers,
  OPERATIONAL_KINDS,
  OVERVIEW_METRICS,
  UNRECORDED_LABEL,
  KIND_LABELS,
  UNIQUE_SOURCE_LABELS,
  RUNNING_VERSION_LABELS,
} from '../src/analytics'
import { channelSchema, downloadSourceSchema, eventKindSchema } from '../src/schema'
import type { EventKind } from '../src/schema'
import {
  clearEvents,
  insertSparkleDownload,
  insertUpdateCheck,
  jst,
  NOW,
} from './analytics-helpers'

afterEach(clearEvents)

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

  it('概要面に出す指標は KIND_LABELS の部分集合', () => {
    // 概要面にだけ現れて他の面のどこにも無い指標を作らないための構造ガード。
    // OVERVIEW_METRICS から漏れた指標は流入面「内訳（全期間の累計）」で読む。
    const shown = new Set(KIND_LABELS.map((entry) => entry.kind))

    for (const metric of OVERVIEW_METRICS) {
      expect(shown.has(metric)).toBe(true)
    }
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

  it('サイト訪問はページで絞らない（ページビューの指標と同じ範囲）', async () => {
    await insertSource(TODAY, 'visit', 'source-a', { page: '/' })
    await insertSource(TODAY, 'visit', 'source-b', { page: '/features' })

    const point = (await dailySeries(env.DB, NOW)).at(-1)

    expect(point?.uniqueSources.visit).toBe(2)
    expect(point?.counts.visit).toBe(2)
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

/**
 * ダウンロード（LP）に絞った参照元の内訳（TASK-549）。
 *
 * 既存の「参照元別」は全イベントで「どこから来訪したか」を見る軸。こちらは
 * `?ref=` が運ぶ「どの面のボタンから押されたか」を見るもので、母集団が違う。
 * 同じ 1 本のクエリから 2 つの母集団を返すため、**片方の絞り込みが他方へ
 * 漏れていないこと**を両方向で確かめる。
 */
describe('ダウンロード（LP）の参照元内訳', () => {
  /** referrer / source を指定して 1 件入れる（既存の insert は両方を持たない）。 */
  async function insertEvent(options: {
    kind: EventKind
    referrer?: string | null
    source?: string | null
  }): Promise<void> {
    await env.DB.prepare(
      'INSERT INTO events (timestamp, kind, visitor_token, referrer, source) VALUES (?, ?, ?, ?, ?)',
    )
      .bind(NOW, options.kind, 'visitor-a', options.referrer ?? null, options.source ?? null)
      .run()
  }

  it('kind=download かつ source=lp の行だけを数える', async () => {
    await insertEvent({ kind: 'download', referrer: 'lp', source: 'lp' })
    await insertEvent({ kind: 'download', referrer: 'lp', source: 'lp' })
    await insertEvent({ kind: 'download', referrer: 'usecases-medical-expenses', source: 'lp' })
    // 母集団の外。混ざったら「LP からの新規獲得」という意味が壊れる。
    await insertEvent({ kind: 'download', referrer: 'lp', source: 'sparkle' })
    await insertEvent({ kind: 'download', referrer: 'lp', source: 'archive' })
    await insertEvent({ kind: 'visit', referrer: 'lp' })

    const summary = await summarizeTraffic(env.DB)

    expect(summary.byDownloadReferrer).toEqual([
      { label: 'lp', count: 2 },
      { label: 'usecases-medical-expenses', count: 1 },
    ])
  })

  it('ref を持たないダウンロードは未記録として並ぶ（行ごと消えない）', async () => {
    await insertEvent({ kind: 'download', referrer: null, source: 'lp' })
    await insertEvent({ kind: 'download', referrer: null, source: 'lp' })
    await insertEvent({ kind: 'download', referrer: 'readme', source: 'lp' })

    const summary = await summarizeTraffic(env.DB)

    expect(summary.byDownloadReferrer).toEqual([
      { label: UNRECORDED_LABEL, count: 2 },
      { label: 'readme', count: 1 },
    ])
  })

  it('全体の「参照元別」は従来どおり全イベントを数え、未記録を含めない', async () => {
    await insertEvent({ kind: 'visit', referrer: 'gh-pages' })
    await insertEvent({ kind: 'download', referrer: 'lp', source: 'lp' })
    await insertEvent({ kind: 'download', referrer: null, source: 'lp' })

    const summary = await summarizeTraffic(env.DB)

    expect(summary.byReferrer).toEqual([
      { label: 'gh-pages', count: 1 },
      { label: 'lp', count: 1 },
    ])
  })
})
