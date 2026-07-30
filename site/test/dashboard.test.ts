import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, describe, expect, it } from 'vitest'
import app from '../src/index'

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
      ' (ts, kind, version, channel, country, os, ua_summary, visitor_day, referrer, as_org)' +
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
    // ユニーク訪問者は visitor_day の異なり数（hash-a / hash-b）
    expect(body).toContain('<span class="value">2</span>')
    expect(body).toContain('v1.10.0')
    expect(body).toContain('macOS 15.0')
    expect(body).toContain('日別ダウンロード（14 日）')
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
})
