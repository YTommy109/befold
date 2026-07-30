import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'
const IP = '203.0.113.5'
const APPCAST_XML = '<?xml version="1.0"?><rss><channel><title>befold</title></channel></rss>'

/** 実リクエストと同じヘッダ構成でルートを叩き、waitUntil の完了まで待つ。 */
async function call(
  path: string,
  headers: Record<string, string> = {},
  cf?: IncomingRequestCfProperties,
): Promise<Response> {
  const request = new Request(`https://befold.example${path}`, {
    headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP', ...headers },
    redirect: 'manual',
    ...(cf === undefined ? {} : { cf }),
  })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, env, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

type EventRow = {
  kind: string
  version: string | null
  channel: string | null
  country: string | null
  os: string | null
  ua_summary: string | null
  visitor_day: string | null
  referrer: string | null
  as_org: string | null
}

async function latestEvent(): Promise<EventRow | null> {
  return await env.DB.prepare(
    'SELECT kind, version, channel, country, os, ua_summary, visitor_day, referrer, as_org' +
      ' FROM events ORDER BY id DESC LIMIT 1',
  ).first<EventRow>()
}

/** 上流（GitHub）への fetch を URL 単位で差し替える。 */
function mockUpstream(responses: Record<string, Response>): void {
  vi.stubGlobal('fetch', (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    const response = responses[url]
    if (response === undefined) throw new Error(`unexpected fetch: ${url}`)
    return Promise.resolve(response)
  })
}

const LATEST_RELEASE_URL = 'https://api.github.com/repos/YTommy109/befold/releases/latest'
const APPCAST_URL = 'https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml'
const APPCAST_DEVELOP_URL =
  'https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml'

afterEach(async () => {
  vi.unstubAllGlobals()
  await env.DB.prepare('DELETE FROM events').run()
})

describe('GET /', () => {
  it('LP を返し visit を記録する', async () => {
    const response = await call('/')

    expect(response.status).toBe(200)
    const body = await response.text()
    expect(body).toContain('befold')
    expect(body).toContain('href="/download"')

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.country).toBe('JP')
  })
})

describe('参照元の記録', () => {
  it('?ref= が付いていればその値を記録する', async () => {
    await call('/?ref=gh-pages')

    expect((await latestEvent())?.referrer).toBe('gh-pages')
  })

  it('?ref= が無ければ Referer のオリジンだけを記録する', async () => {
    await call('/', { Referer: 'https://news.ycombinator.com/item?id=123' })

    expect((await latestEvent())?.referrer).toBe('https://news.ycombinator.com')
  })

  it('自サイト内の遷移は参照元として記録しない', async () => {
    await call('/', { Referer: 'https://befold.example/' })

    expect((await latestEvent())?.referrer).toBeNull()
  })

  it('参照元が無い直接アクセスでもイベント自体は記録される', async () => {
    await call('/')

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.referrer).toBeNull()
  })
})

describe('接続元組織（ASN）の記録', () => {
  it('request.cf.asOrganization があれば記録する', async () => {
    await call('/', {}, { asOrganization: 'Google LLC' } as IncomingRequestCfProperties)

    expect((await latestEvent())?.as_org).toBe('Google LLC')
  })

  it('request.cf が無い（ローカル・テスト相当）環境でもイベント自体は記録される', async () => {
    const response = await call('/')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.as_org).toBeNull()
  })
})

describe('GET /download', () => {
  it('最新リリースの DMG へ 302 リダイレクトし download を記録する', async () => {
    mockUpstream({
      [LATEST_RELEASE_URL]: Response.json({
        tag_name: 'v1.2.3',
        assets: [
          { name: 'befold-v1.2.3.dmg', browser_download_url: 'https://example.test/befold.dmg' },
        ],
      }),
    })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe('https://example.test/befold.dmg')

    const event = await latestEvent()
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.channel).toBe('stable')
  })

  it('GitHub API が失敗してもリリース一覧へリダイレクトする', async () => {
    mockUpstream({ [LATEST_RELEASE_URL]: new Response('boom', { status: 500 }) })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe(
      'https://github.com/YTommy109/befold/releases/latest',
    )
    expect((await latestEvent())?.version).toBeNull()
  })
})

describe('appcast プロキシ', () => {
  it('/appcast.xml が GitHub の appcast を返し update_check を記録する', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast.xml', { 'User-Agent': 'befold/1.2.3 Sparkle/2.6.4' })

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('xml')
    expect(await response.text()).toBe(APPCAST_XML)

    const event = await latestEvent()
    expect(event?.kind).toBe('update_check')
    expect(event?.channel).toBe('stable')
    expect(event?.ua_summary).toBe('Sparkle')
  })

  it('/appcast-develop.xml が develop チャンネルとして記録される', async () => {
    mockUpstream({ [APPCAST_DEVELOP_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast-develop.xml')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('上流が失敗したら 502 を返す', async () => {
    mockUpstream({ [APPCAST_URL]: new Response('nope', { status: 404 }) })

    const response = await call('/appcast.xml')

    expect(response.status).toBe(502)
  })
})

describe('計測の best-effort 性', () => {
  it('D1 が失敗してもレスポンスは成功する', async () => {
    const brokenEnv = {
      ...env,
      DB: {
        prepare() {
          throw new Error('D1 unavailable')
        },
      } as unknown as D1Database,
    }
    const request = new Request('https://befold.example/', { headers: { 'User-Agent': UA } })
    const ctx = createExecutionContext()

    const response = await app.fetch(request, brokenEnv, ctx)
    await waitOnExecutionContext(ctx)

    expect(response.status).toBe(200)
    expect(await latestEvent()).toBeNull()
  })
})

describe('プライバシー', () => {
  it('生 IP と完全 UA は保存しない', async () => {
    await call('/')

    const event = await latestEvent()
    const stored = JSON.stringify(event)
    expect(stored).not.toContain(IP)
    expect(stored).not.toContain('AppleWebKit')
    expect(event?.os).toBe('macOS 14.5')
    expect(event?.ua_summary).toBe('Safari')
    expect(event?.visitor_day).toMatch(/^[0-9a-f]{64}$/)
  })
})
