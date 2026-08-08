import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'
import app from '../src/index'
import { summarize } from '../src/analytics'
import { renderSummarySections } from '../src/views/dashboard'

const AUTH_HEADERS = { Authorization: `Basic ${btoa('owner:test-password')}` }

async function call(
  path: string,
  headers: Record<string, string> = {},
  overrides: Partial<Env> = {},
): Promise<Response> {
  const request = new Request(`https://befold.example${path}`, { headers })
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
  } = {},
): Promise<number> {
  const result = await env.DB.prepare(
    'INSERT INTO events' +
      ' (timestamp, kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org)' +
      " VALUES (?, ?, ?, 'stable', ?, ?, 'Safari', ?, ?, ?) RETURNING id",
  )
    .bind(
      extra.ts ?? Date.now(),
      kind,
      extra.version ?? null,
      extra.country ?? null,
      extra.os ?? null,
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

describe('Basic 認証による保護', () => {
  it('認証情報が無ければ 401 と WWW-Authenticate を返す', async () => {
    const response = await call('/dashboard')

    expect(response.status).toBe(401)
    expect(response.headers.get('WWW-Authenticate')).toContain('Basic')
    expect((await call('/dashboard/stream')).status).toBe(401)
  })

  it('パスワードが違えば 401 を返す', async () => {
    const wrong = { Authorization: `Basic ${btoa('owner:wrong')}` }

    expect((await call('/dashboard', wrong)).status).toBe(401)
  })

  it('パスワード未設定なら 503 で閉じる（素通しさせない）', async () => {
    const response = await call('/dashboard', AUTH_HEADERS, {
      DASHBOARD_PASSWORD: '',
    } as Partial<Env>)

    expect(response.status).toBe(503)
  })

  it('正しい認証情報なら 200 を返す', async () => {
    expect((await call('/dashboard', AUTH_HEADERS)).status).toBe(200)
  })

  it('公開ルートは認証情報が無くても 200 のままである', async () => {
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

describe('グラフ描画', () => {
  it('日毎の推移と時間帯分布がインライン SVG で描画される', async () => {
    await seed('visit')
    await seed('download')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).toContain('<svg class="chart"')
    expect(body).toContain('<rect class="chart-bar"')
    // 外部ホストへのリクエストを発生させない（インライン化されている）。
    expect(body).not.toMatch(/<(script|link|img)[^>]+(src|href)="https?:/)
  })

  it('SSE で配信される HTML にもグラフが含まれる（再描画フックが要らない）', async () => {
    await seed('visit')

    const summaryHtml = renderSummarySections(await summarize(env.DB, Date.now()))

    expect(summaryHtml).toContain('<svg class="chart"')
    expect(summaryHtml).toContain('<rect class="chart-bar"')
  })

  it('データが 0 件でも描画が壊れない', async () => {
    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    // 全系列が 0 件なので棒は描かれず、空状態の文言になる。
    expect(body).toContain('期間内のデータなし')
    expect(body).not.toContain('NaN')
    expect(body).not.toContain('<rect class="chart-bar"')
  })

  it('1 点のみ・全値同一でも棒の高さが NaN にならない', async () => {
    // 同じ日・同じ時刻に同数のイベントを置き、最大値と各値が等しい状況にする。
    await seed('visit')
    await seed('visit')

    const body = await (await call('/dashboard', AUTH_HEADERS)).text()

    expect(body).not.toContain('NaN')
    expect(body).toContain('<rect class="chart-bar"')
    // 最大値と等しい棒はプロット高さいっぱいになる（126 = 140 - 14）。
    expect(body).toContain('height="126"')
  })
})
