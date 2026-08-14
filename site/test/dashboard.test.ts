import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest'
import app from '../src/index'
import { summarize } from '../src/analytics'
import { LEGACY_HOST, LEGACY_STAGING_HOST } from '../src/lib/hosts'
import { installAccessKeys, removeAccessKeys } from './access-helpers'
import { renderSummarySections } from '../src/views/dashboard'

/**
 * Access が付ける JWT ヘッダ。中身は beforeAll で埋める（署名に鍵生成が要る）。
 * 参照は同じオブジェクトのまま各テストへ渡るので、ここを書き換えれば全体に効く。
 */
const AUTH_HEADERS: Record<string, string> = {}

let signJwt: (claims: Record<string, unknown>) => Promise<string>

beforeAll(async () => {
  const access = await installAccessKeys()
  signJwt = access.sign
  Object.assign(AUTH_HEADERS, await access.headers())
})

afterAll(() => {
  removeAccessKeys()
})

async function call(
  path: string,
  headers: Record<string, string> = {},
  overrides: Partial<Env> = {},
  origin = 'https://befold.degino.com',
): Promise<Response> {
  const request = new Request(`${origin}${path}`, { headers })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, { ...env, ...overrides }, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

/** テスト用のイベントを 1 件投入し、その id を返す。 */
async function seed(
  kind: string,
  extra: {
    version?: string
    country?: string
    os?: string
    visitorDay?: string
    ts?: number
    referrer?: string
    asOrg?: string
    uaSummary?: string
  } = {},
): Promise<number> {
  const result = await env.DB.prepare(
    'INSERT INTO events' +
      ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org)' +
      " VALUES (?, ?, ?, 'stable', ?, ?, ?, ?, ?, ?) RETURNING id",
  )
    .bind(
      extra.ts ?? Date.now(),
      kind,
      extra.version ?? null,
      extra.country ?? null,
      extra.os ?? null,
      extra.uaSummary ?? 'Safari',
      extra.visitorDay ?? 'hash-a',
      extra.referrer ?? null,
      extra.asOrg ?? null,
    )
    .first<{ id: number }>()

  return result?.id ?? 0
}

afterEach(async () => {
  await env.DB.prepare('DELETE FROM events').run()
})

describe('Cloudflare Access による保護', () => {
  it('JWT が無ければ 401 を返す', async () => {
    expect((await call('/dashboard')).status).toBe(401)
    expect((await call('/dashboard/stream')).status).toBe(401)
  })

  it('署名が壊れた JWT は 403 を返す', async () => {
    const token = await signJwt({})
    const tampered = { 'Cf-Access-Jwt-Assertion': `${token.slice(0, -4)}AAAA` }

    expect((await call('/dashboard', tampered)).status).toBe(403)
  })

  it('別アプリ向けの AUD を持つ JWT は 403 を返す', async () => {
    const headers = { 'Cf-Access-Jwt-Assertion': await signJwt({ aud: ['other-app'] }) }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('発行者が team domain と違う JWT は 403 を返す', async () => {
    const headers = {
      'Cf-Access-Jwt-Assertion': await signJwt({ iss: 'https://evil.cloudflareaccess.com' }),
    }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('期限切れの JWT は 403 を返す', async () => {
    const expired = Math.floor(Date.now() / 1000) - 60
    const headers = { 'Cf-Access-Jwt-Assertion': await signJwt({ exp: expired }) }

    expect((await call('/dashboard', headers)).status).toBe(403)
  })

  it('Access が未設定なら 503 で閉じる（素通しさせない）', async () => {
    const response = await call('/dashboard', AUTH_HEADERS, {
      ACCESS_AUD: '',
    } as Partial<Env>)

    expect(response.status).toBe(503)
  })

  it('未設定でも localhost 以外は素通ししない', async () => {
    const response = await call('/dashboard', AUTH_HEADERS, { ACCESS_AUD: '' } as Partial<Env>)

    expect(response.status).not.toBe(200)
  })

  it('ローカル開発（localhost かつ未設定）だけは素通しする', async () => {
    const response = await call(
      '/dashboard',
      {},
      { ACCESS_TEAM_DOMAIN: '', ACCESS_AUD: '' } as Partial<Env>,
      'http://localhost:8787',
    )

    expect(response.status).toBe(200)
  })

  it('有効な JWT なら 200 を返す', async () => {
    expect((await call('/dashboard', AUTH_HEADERS)).status).toBe(200)
  })

  it('旧ホストの /dashboard と /dashboard/* は 404 を返す', async () => {
    for (const host of [LEGACY_HOST, LEGACY_STAGING_HOST]) {
      const origin = `https://${host}`

      expect((await call('/dashboard', AUTH_HEADERS, {}, origin)).status).toBe(404)
      expect((await call('/dashboard/stream', AUTH_HEADERS, {}, origin)).status).toBe(404)
    }
  })

  it('公開ルートは JWT が無くても 200 のままである', async () => {
    expect((await call('/')).status).toBe(200)
  })
})

describe('集計の表示', () => {
  it('日付・時刻が JST 基準であることが画面に明示される', async () => {
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('日付・時刻はすべて JST (UTC+9) 基準')
  })

  it('JST 基準の明示は SSE の差し替え範囲（#summary）の外に置く', async () => {
    await seed('visit')

    const summaryHtml = renderSummarySections(await summarize(env.DB, Date.now()))

    // #summary は SSE が毎周期 innerHTML で丸ごと置き換えるため、
    // 静的なテキストを含めない（含めると毎回同じ文字列を送り直すことになる）。
    expect(summaryHtml).not.toContain('日付・時刻はすべて JST (UTC+9) 基準')
  })

  it('種別ごとの合計・バージョン別・国別・OS 別が描画される', async () => {
    await seed('visit', { country: 'JP', os: 'macOS 14.5' })
    await seed('visit', { country: 'US', os: 'macOS 15.0', visitorDay: 'hash-b' })
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 14.5' })
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 14.5' })
    await seed('update_check', { country: 'JP', os: 'macOS 14.5' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<span class="value" id="count-visit">2</span>')
    expect(body).toContain('<span class="value" id="count-download">2</span>')
    expect(body).toContain('<span class="value" id="count-update_check">1</span>')
    // 延べ訪問者は visitor_token の異なり数（hash-a / hash-b）
    expect(body).toContain('<span class="value">2</span>')
    expect(body).toContain('v1.10.0')
    expect(body).toContain('macOS 15.0')
    // セクション見出しから集計期間が読み取れる。
    expect(body).toContain('<h2>累計（全期間）</h2>')
    expect(body).toContain('<h2>本日（JST 0 時から）</h2>')
    expect(body).toContain('<h2>日毎の推移（直近 14 日）</h2>')
    expect(body).toContain('<h2>時間帯分布（直近 14 日・JST）</h2>')
    expect(body).toContain('<h2>内訳（全期間の累計）</h2>')
  })

  it('参照元別が上位順で描画され、参照元なしは集計から除かれる', async () => {
    await seed('visit', { referrer: 'gh-pages' })
    await seed('visit', { referrer: 'gh-pages' })
    await seed('visit', { referrer: 'https://news.ycombinator.com' })
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('参照元別')
    expect(body).toContain('gh-pages')
    expect(body).toContain('https://news.ycombinator.com')
    expect(body.indexOf('gh-pages')).toBeLessThan(body.indexOf('https://news.ycombinator.com'))
  })

  it('接続元組織別が上位順で描画され、組織なしは集計から除かれる', async () => {
    await seed('visit', { asOrg: 'Google LLC' })
    await seed('visit', { asOrg: 'Google LLC' })
    await seed('visit', { asOrg: 'NTT Communications' })
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('接続元組織別')
    expect(body).toContain('Google LLC')
    expect(body).toContain('NTT Communications')
    expect(body.indexOf('Google LLC')).toBeLessThan(body.indexOf('NTT Communications'))
  })

  it('人間の訪問とロボットの巡回が分離して描画され、ロボットは種類別に見える', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })
    await seed('visit', { uaSummary: 'bot:GPTBot' })
    await seed('visit', { uaSummary: 'bot:other' })
    await seed('visit', { uaSummary: 'Safari' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<h2>人間の訪問とロボットの巡回（全期間の累計）</h2>')
    expect(body).toContain('<span class="value">3</span><span class="label">ロボット（クローラ）</span>')
    expect(body).toContain('<span class="value">1</span><span class="label">人間のクライアント</span>')

    const humanTable = body.indexOf('人間: クライアント種別')
    const botTable = body.indexOf('ロボット: 種類別')
    expect(humanTable).toBeGreaterThan(-1)
    expect(botTable).toBeGreaterThan(humanTable)
    // 種類は人間側の表に混ざらず、ロボット側の表にだけ現れる。
    expect(body.slice(humanTable, botTable)).not.toContain('bot:GPTBot')
    expect(body.slice(botTable)).toContain('bot:GPTBot')
    expect(body.slice(botTable)).toContain('bot:other')
  })

  it('過去データを遡って分類できないことが注記から読み取れる', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('2026-08-09')
    expect(body).toContain('より前に記録されたイベントは遡って分類できず')
  })

  it('他の集計がロボットを除いた数であることが注記から読み取れる', async () => {
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('ロボットと判定した巡回を除いた数')
  })

  it('OS 別が 3 指標それぞれに分かれて集計される', async () => {
    await seed('visit', { os: 'macOS 14.5' })
    await seed('download', { os: 'macOS 15.0' })
    await seed('update_check', { os: 'macOS 13.6' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    const visitOS = body.indexOf('ページアクセス: OS 別')
    const downloadOS = body.indexOf('ダウンロード: OS 別')
    const updateOS = body.indexOf('アップデート確認: OS 別')
    expect(visitOS).toBeGreaterThan(-1)
    expect(downloadOS).toBeGreaterThan(visitOS)
    expect(updateOS).toBeGreaterThan(downloadOS)
    // 各指標の表には、その指標のイベントの OS だけが現れる
    expect(body.slice(visitOS, downloadOS)).toContain('macOS 14.5')
    expect(body.slice(visitOS, downloadOS)).not.toContain('macOS 15.0')
    expect(body.slice(downloadOS, updateOS)).toContain('macOS 15.0')
    expect(body.slice(downloadOS, updateOS)).not.toContain('macOS 13.6')
    expect(body.slice(updateOS)).toContain('macOS 13.6')
  })

  it('接続元組織別が 3 指標それぞれに分かれて集計される', async () => {
    await seed('visit', { asOrg: 'Google LLC' })
    await seed('download', { asOrg: 'NTT Communications' })
    await seed('update_check', { asOrg: 'KDDI CORPORATION' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    const visitOrg = body.indexOf('ページアクセス: 接続元組織別')
    const downloadOrg = body.indexOf('ダウンロード: 接続元組織別')
    const updateOrg = body.indexOf('アップデート確認: 接続元組織別')
    expect(visitOrg).toBeGreaterThan(-1)
    expect(downloadOrg).toBeGreaterThan(visitOrg)
    expect(updateOrg).toBeGreaterThan(downloadOrg)
    expect(body.slice(visitOrg, downloadOrg)).toContain('Google LLC')
    expect(body.slice(visitOrg, downloadOrg)).not.toContain('NTT Communications')
    expect(body.slice(downloadOrg, updateOrg)).toContain('NTT Communications')
    expect(body.slice(updateOrg)).toContain('KDDI CORPORATION')
  })

  it('イベントが無くてもエラーにならない', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<span class="value" id="count-visit">0</span>')
    expect(body).toContain('データなし')
  })
})

describe('SSE ストリーム', () => {
  it('after より新しいイベントを push する', async () => {
    const oldId = await seed('visit')
    await seed('download', { version: 'v1.10.0' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/event-stream')

    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    // 初回ポーリング分（接続コメント＋差分）が届くまで読む。
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).toContain(': connected')
    expect(received).toContain('event: event')
    expect(received).toContain('"kind":"download"')
    expect(received).toContain('"version":"v1.10.0"')
    // after より前のイベントは含まない
    expect(received).not.toContain('"kind":"visit"')
  })

  it('新着イベントがあれば集計セクションの HTML を summary イベントで配信する', async () => {
    const oldId = await seed('visit')
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 15.0' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).toContain('event: summary')
    const dataLine = received.split('event: summary\ndata: ')[1]?.split('\n')[0] ?? ''
    const html = JSON.parse(dataLine) as string
    // サーバー側で描画済みの集計表がそのまま届く（クライアントは差し替えるだけ）。
    expect(html).toContain('<h2>日毎の推移（直近 14 日）</h2>')
    expect(html).toContain('v1.10.0')
    expect(html).toContain('<span class="value" id="count-download">1</span>')
    // data 行は 1 行に収まっている
    expect(html).not.toContain('\n')
  })

  it('ロボットの巡回は event として流さないが、集計は配信し直す', async () => {
    // カーソルを人間の行だけで進めると、ボットしか来なかった周期で位置が進まず
    // 集計（ロボットのセクションを含む）が更新されないままになる。
    const oldId = await seed('visit')
    await seed('visit', { uaSummary: 'bot:GPTBot' })

    const response = await call(`/dashboard/stream?after=${oldId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).not.toContain('event: event')
    expect(received).toContain('event: summary')
    const dataLine = received.split('event: summary\ndata: ')[1]?.split('\n')[0] ?? ''
    const html = JSON.parse(dataLine) as string
    // 巡回はロボットのセクションにだけ現れ、ページアクセス数には入らない。
    expect(html).toContain('bot:GPTBot')
    expect(html).toContain('<span class="value" id="count-visit">1</span>')
  })

  it('新着イベントが無いポーリング周期では summary を配信しない', async () => {
    const lastId = await seed('visit')

    const response = await call(`/dashboard/stream?after=${lastId}`, AUTH_HEADERS)
    const reader = response.body!.getReader()
    const decoder = new TextDecoder()
    let received = ''
    while (!received.includes('keep-alive')) {
      const { value, done } = await reader.read()
      if (done) break
      received += decoder.decode(value, { stream: true })
    }
    await reader.cancel()

    expect(received).not.toContain('event: summary')
  })
})

/** `<h2>見出し` から次の `<h2>` 直前までを 1 節として切り出す。 */
const section = (html: string, heading: string): string => {
  const start = html.indexOf(`<h2>${heading}`)
  expect(start).toBeGreaterThanOrEqual(0)
  const rest = html.slice(start)
  const end = rest.indexOf('<h2>', 1)
  return end === -1 ? rest : rest.slice(0, end)
}

describe('グラフ描画', () => {
  it('日毎の推移と時間帯分布がインライン SVG で描画される', async () => {
    await seed('visit')
    await seed('download')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<svg class="chart"')
    expect(body).toContain('<rect class="chart-bar chart-bar-1"')
    // 外部ホストへのリクエストを発生させない（インライン化されている）。
    expect(body).not.toMatch(/<(script|link|img)[^>]+(src|href)="https?:/)
  })

  it('系列ごとに別チャートを並べず、1 節 1 枚のグループ化バーチャートにまとめる', async () => {
    await seed('visit')
    await seed('download')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()
    const daily = section(body, '日毎の推移')
    const hourly = section(body, '時間帯分布')

    expect(daily.match(/<svg class="chart"/g)).toHaveLength(1)
    expect(hourly.match(/<svg class="chart"/g)).toHaveLength(1)
    // 日毎は 4 指標 + ユニーク訪問者の 5 系列、時間帯は 4 指標。
    expect(daily).toContain('chart-bar-5')
    expect(hourly).toContain('chart-bar-4')
    expect(hourly).not.toContain('chart-bar-5')
  })

  it('チャートを持つ節には凡例があり、表は置かない', async () => {
    await seed('visit')
    await seed('download', { version: 'v1.10.0', country: 'JP', os: 'macOS 15.0' })

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()
    const daily = section(body, '日毎の推移')
    const hourly = section(body, '時間帯分布')

    expect(daily).toContain('<ul class="legend">')
    expect(daily).toContain('<span class="swatch swatch-5"')
    expect(hourly).toContain('<ul class="legend">')
    // 色以外の手掛かり（凡例の並び順 = グループ内のバーの並び順）を残す。
    expect(daily).toContain('<span class="order">1.</span>')
    expect(daily).not.toContain('<table>')
    expect(hourly).not.toContain('<table>')
    // チャートを持たない節の表は残す。
    expect(section(body, '内訳')).toContain('<table>')
    expect(section(body, '最新イベント')).toContain('<table>')
  })

  it('日付・時間帯のラベルを間引かずに全件描く', async () => {
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    // 直近 14 日 + 24 時間帯。
    expect(section(body, '日毎の推移').match(/class="chart-label"/g)).toHaveLength(14)
    expect(section(body, '時間帯分布').match(/class="chart-label"/g)).toHaveLength(24)
  })

  it('SSE で配信される HTML にもグラフと凡例が含まれる（再描画フックが要らない）', async () => {
    await seed('visit')

    const summaryHtml = renderSummarySections(await summarize(env.DB, Date.now()))

    expect(summaryHtml).toContain('<svg class="chart"')
    expect(summaryHtml).toContain('<rect class="chart-bar chart-bar-1"')
    expect(summaryHtml).toContain('<ul class="legend">')
  })

  it('データが 0 件でも描画が壊れない', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    // 全系列が 0 件なので棒は描かれず、空状態の文言になる。
    expect(body).toContain('期間内のデータなし')
    expect(body).not.toContain('NaN')
    expect(body).not.toContain('<rect class="chart-bar')
  })

  it('1 点のみ・全値同一でも棒の高さが NaN にならない', async () => {
    // 同じ日・同じ時刻に同数のイベントを置き、最大値と各値が等しい状況にする。
    await seed('visit')
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).not.toContain('NaN')
    expect(body).toContain('<rect class="chart-bar chart-bar-1"')
    // 最大値と等しい棒は棒の描画高さいっぱいになる（180 = 220 - 22 - 18）。
    expect(body).toContain('height="180"')
  })
})
