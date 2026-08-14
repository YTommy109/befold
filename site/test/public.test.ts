import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, describe, expect, it, vi } from 'vitest'
import app from '../src/index'

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'
const IP = '203.0.113.5'
const APPCAST_XML = '<?xml version="1.0"?><rss><channel><title>befold</title></channel></rss>'
const DEVELOP_XML = '<?xml version="1.0"?><rss><channel><title>befold-dev</title></channel></rss>'

/** テストの既定オリジン。ホストに依存しない振る舞いはこれで確かめる。 */
const DEFAULT_ORIGIN = 'https://befold.example'

/** 実リクエストと同じヘッダ構成でルートを叩き、waitUntil の完了まで待つ。 */
async function call(
  path: string,
  headers: Record<string, string> = {},
  cf?: IncomingRequestCfProperties,
  origin: string = DEFAULT_ORIGIN,
): Promise<Response> {
  const request = new Request(`${origin}${path}`, {
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
  visitor_token: string | null
  referrer: string | null
  as_org: string | null
  source: string | null
}

async function latestEvent(): Promise<EventRow | null> {
  return await env.DB.prepare(
    'SELECT kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org, source' +
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

  const { objects } = await env.DIST.list()
  await Promise.all(objects.map((object) => env.DIST.delete(object.key)))

  // caches.default はテスト間で共有される。前のテストの appcast が残ると
  // 次のテストが R2 を読まずにそれを返してしまう。
  await Promise.all(
    ['/appcast.xml', '/appcast-develop.xml'].map((path) =>
      caches.default.delete(`https://befold.example${path}`),
    ),
  )
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

  it('R2 に最新ポインタがあれば DMG を直接返し source=lp を記録する', async () => {
    await env.DIST.put(
      'releases/latest.json',
      JSON.stringify({ version: 'v1.2.3', file: 'befold-v1.2.3.dmg' }),
    )
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/download')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')
    expect(response.headers.get('Content-Disposition')).toContain('befold-v1.2.3.dmg')

    const event = await latestEvent()
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.source).toBe('lp')
  })

  it('latest.json が壊れていれば GitHub 解決へ落とす', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"not-a-tag"}')
    mockUpstream({ [LATEST_RELEASE_URL]: new Response('boom', { status: 500 }) })

    const response = await call('/download')

    expect(response.status).toBe(302)
    expect((await latestEvent())?.source).toBe('lp')
  })
})

describe('GET /dl/:tag/:file', () => {
  it('R2 の DMG を返し source=sparkle を記録する', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')

    const event = await latestEvent()
    expect(event?.kind).toBe('download')
    expect(event?.version).toBe('v1.2.3')
    expect(event?.channel).toBe('stable')
    expect(event?.source).toBe('sparkle')
  })

  it('dev タグは develop チャンネルとして記録する', async () => {
    await env.DIST.put('releases/v1.2.3-dev.1/befold-v1.2.3-dev.1.dmg', 'DMG-BODY')

    const response = await call('/dl/v1.2.3-dev.1/befold-v1.2.3-dev.1.dmg')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('R2 に無ければ 404 ではなく GitHub Releases へ 302 する', async () => {
    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    // Sparkle は enclosure の 404 を更新失敗として扱うため、404 は返さない。
    expect(response.status).toBe(302)
    expect(response.headers.get('Location')).toBe(
      'https://github.com/YTommy109/befold/releases/download/v1.2.3/befold-v1.2.3.dmg',
    )
  })

  it('DMG 以外のオブジェクトはパス検証で弾き R2 を読まない', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"v1.2.3","file":"befold-v1.2.3.dmg"}')

    const response = await call('/dl/v1.2.3/..%2Flatest.json')

    expect(response.status).toBe(302)
    expect(await response.text()).not.toContain('v1.2.3')
  })

  it('タグの形が合わないリクエストは R2 を読まない', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/dl/appcast/befold-v1.2.3.dmg')

    expect(response.status).toBe(302)
    expect(await response.text()).not.toBe('DMG-BODY')
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

  it('R2 に appcast があれば GitHub を読まずにそちらを返す', async () => {
    const r2Body = '<?xml version="1.0"?><rss><channel><title>from-r2</title></channel></rss>'
    await env.DIST.put('appcast.xml', r2Body)
    // GitHub への fetch が起きたらこのスタブが例外を投げる。
    mockUpstream({})

    const response = await call('/appcast.xml')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe(r2Body)
    expect((await latestEvent())?.kind).toBe('update_check')
  })

  it('develop チャンネルも R2 の appcast-develop.xml を見る', async () => {
    await env.DIST.put('appcast-develop.xml', APPCAST_XML)
    mockUpstream({})

    const response = await call('/appcast-develop.xml')

    expect(response.status).toBe(200)
    expect((await latestEvent())?.channel).toBe('develop')
  })

  it('2 回目は Worker 側キャッシュから返し R2 を読まない', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    mockUpstream({})

    expect((await call('/appcast.xml')).status).toBe(200)

    const get = vi.spyOn(env.DIST, 'get')
    const second = await call('/appcast.xml')

    expect(second.status).toBe(200)
    expect(await second.text()).toBe(APPCAST_XML)
    expect(get).not.toHaveBeenCalled()
  })

  it('キャッシュヒット時も update_check を記録する', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    mockUpstream({})

    await call('/appcast.xml')
    await call('/appcast.xml')

    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM events WHERE kind = 'update_check'",
    ).first<{ n: number }>()
    expect(count?.n).toBe(2)
  })

  it('チャンネルごとに別のキャッシュを持つ', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    await env.DIST.put('appcast-develop.xml', DEVELOP_XML)
    mockUpstream({})

    await call('/appcast.xml')
    const develop = await call('/appcast-develop.xml')

    expect(await develop.text()).toBe(DEVELOP_XML)
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
    expect(event?.visitor_token).toMatch(/^[0-9a-f]{64}$/)
  })
})

describe('OGP メタタグ', () => {
  it('og:image と og:url をリクエストの origin から絶対 URL で出す', async () => {
    const html = await (await call('/')).text()

    expect(html).toContain(
      '<meta property="og:image" content="https://befold.example/images/ogp.png"/>',
    )
    expect(html).toContain('<meta property="og:url" content="https://befold.example/"/>')
  })

  it('twitter:card は大判カードにする', async () => {
    const html = await (await call('/')).text()

    expect(html).toContain('<meta name="twitter:card" content="summary_large_image"/>')
  })

  it('ホストが変わっても og:url がそのホストを指す（ハードコードしない）', async () => {
    const request = new Request('https://befold-staging.example/', {
      headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP' },
    })
    const ctx = createExecutionContext()
    const html = await (await app.fetch(request, env, ctx)).text()
    await waitOnExecutionContext(ctx)

    expect(html).toContain('<meta property="og:url" content="https://befold-staging.example/"/>')
    expect(html).toContain(
      '<meta property="og:image" content="https://befold-staging.example/images/ogp.png"/>',
    )
  })

  it('og:title と og:description は title / description と同じ文字列にする', async () => {
    const html = await (await call('/')).text()

    const title = html.match(/<title>(.*?)<\/title>/)?.[1]
    const description = html.match(/<meta name="description" content="(.*?)"\/>/)?.[1]

    expect(title).toBeTruthy()
    expect(description).toBeTruthy()
    expect(html).toContain(`<meta property="og:title" content="${title}"/>`)
    expect(html).toContain(`<meta property="og:description" content="${description}"/>`)
  })
})

describe('対象 OS の明示', () => {
  it('ファーストビューのリード文で日英とも Mac 専用だと分かる', async () => {
    const html = await (await call('/')).text()
    const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/)?.[1]

    expect(hero).toBeTruthy()
    expect(hero).toContain('Mac 専用')
    expect(hero).toContain('Mac-only')
  })

  it('ダウンロードボタンの近辺で macOS 14 以降だと分かる', async () => {
    const html = await (await call('/')).text()
    const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/)?.[1] ?? ''

    expect(hero).toContain('macOS 14 (Sonoma) 以降が必要です')
    expect(hero).toContain('Requires macOS 14 (Sonoma) or later')
    // 注記はボタンより後ろに置き、クリック前に目に入るようにする。
    expect(hero.indexOf('btn-primary')).toBeLessThan(hero.indexOf('hero-note'))
  })
})

describe('構造化データ (JSON-LD)', () => {
  it('SoftwareApplication として macOS 専用・ダウンロード先を示す', async () => {
    const html = await (await call('/')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]

    expect(json).toBeTruthy()
    const data = JSON.parse(json as string)
    expect(data['@type']).toBe('SoftwareApplication')
    expect(data.operatingSystem).toBe('macOS 14 (Sonoma) or later')
    expect(data.applicationCategory).toBe('DeveloperApplication')
    expect(data.downloadUrl).toBe('https://befold.example/download')
    expect(data.url).toBe('https://befold.example/')
  })

  it('description は <meta name="description"> と同じ文字列にする', async () => {
    const html = await (await call('/')).text()
    const description = html.match(/<meta name="description" content="(.*?)"\/>/)?.[1]
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]

    expect(JSON.parse(json as string).description).toBe(description)
  })
})

describe('robots.txt / sitemap.xml', () => {
  it('robots.txt は 200 / text/plain で dashboard を除外し sitemap を指す', async () => {
    const response = await call('/robots.txt')

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('text/plain')
    const body = await response.text()
    expect(body).toContain('Disallow: /dashboard')
    expect(body).toContain('Sitemap: https://befold.example/sitemap.xml')
  })

  it('sitemap.xml は 200 / application/xml で公開ページのみ列挙する', async () => {
    const response = await call('/sitemap.xml')

    expect(response.status).toBe(200)
    expect(response.headers.get('Content-Type')).toContain('application/xml')
    const body = await response.text()
    expect(body).toContain('<loc>https://befold.example/</loc>')
    expect(body).toContain('<loc>https://befold.example/features</loc>')
    expect(body).not.toContain('/dashboard')
    expect(body).not.toContain('/healthz')
  })

  it('robots.txt / sitemap.xml はアクセスを visit として記録しない', async () => {
    await call('/robots.txt')
    await call('/sitemap.xml')

    expect(await latestEvent()).toBeNull()
  })
})

describe('GET /features', () => {
  it('200 を返し、機能・対応ファイルタイプ・ショートカット・FAQ を含む', async () => {
    const response = await call('/features')

    expect(response.status).toBe(200)
    const body = await response.text()
    expect(body).toContain('対応ファイルタイプ')
    expect(body).toContain('Supported File Types')
    expect(body).toContain('キーボードショートカット')
    expect(body).toContain('Keyboard Shortcuts')
    expect(body).toContain('よくある質問')
    expect(body).toContain('Frequently Asked Questions')
  })

  it('日英どちらの本文も DOM に含まれ、英語側は hidden で出す', async () => {
    const body = await (await call('/features')).text()

    // 言語切替は [lang] 属性 + hidden の付け外しで行うため、両方が出力されている必要がある。
    expect(body).toContain('lang="ja"')
    expect(body).toMatch(/lang="en"[^>]*hidden/)
  })

  it('対応ファイルタイプ表に主要な拡張子が並ぶ', async () => {
    const body = await (await call('/features')).text()

    for (const extension of ['.mmd', '.md', '.svg', '.html', '.csv', '.tsv', '.pdf', '.swift']) {
      expect(body, `${extension} が表に無い`).toContain(extension)
    }
  })

  it('canonical と og:url が /features を指す', async () => {
    const body = await (await call('/features')).text()

    expect(body).toContain('<link rel="canonical" href="https://befold.example/features"/>')
    expect(body).toContain('content="https://befold.example/features"')
  })

  it('FAQPage の JSON-LD を出力する', async () => {
    const body = await (await call('/features')).text()
    const json = body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]

    expect(json).toBeTruthy()
    const data = JSON.parse(json as string)
    expect(data['@type']).toBe('FAQPage')
    expect(Array.isArray(data.mainEntity)).toBe(true)
    expect(data.mainEntity.length).toBeGreaterThan(0)

    for (const entry of data.mainEntity) {
      expect(entry['@type']).toBe('Question')
      expect(entry.name.length).toBeGreaterThan(0)
      expect(entry.acceptedAnswer['@type']).toBe('Answer')
      // 構造化データの答えはページ上に見えている必要がある。
      expect(body).toContain(entry.acceptedAnswer.text.slice(0, 40))
    }
  })

  it('visit として記録せず、キャッシュ可能なレスポンスにする', async () => {
    const response = await call('/features')

    expect(response.headers.get('Cache-Control')).toContain('max-age=3600')
    expect(await latestEvent()).toBeNull()
  })
})

describe('LP から詳細ページへの導線', () => {
  it('LP に /features への内部リンクがある', async () => {
    const body = await (await call('/')).text()

    expect(body).toContain('href="/features"')
  })
})

/**
 * 旧 workers.dev ホストの扱い（ADR 0007 の決定 1・2）。
 *
 * 旧ホストは恒久的に生かし続ける必要がある。出荷済みアプリの Sparkle フィード URL
 * と、配信済み appcast に埋まった enclosure URL は後から変更できないため、
 * `/appcast*.xml` と `/dl/*` が旧ホストで 200 を返さなくなると更新経路が止まる。
 * リダイレクトは HTML ページの肯定列挙のみで行う。
 */
describe('旧ホストからのリダイレクト', () => {
  const LEGACY = 'https://befold.tommy109.workers.dev'
  const LEGACY_STAGING = 'https://befold-staging.tommy109.workers.dev'

  const legacy = (path: string, headers: Record<string, string> = {}) =>
    call(path, headers, undefined, LEGACY)

  it('LP は新ドメインの同一パスへ 301 で送る', async () => {
    const response = await legacy('/')

    expect(response.status).toBe(301)
    expect(response.headers.get('Location')).toBe('https://befold.degino.com/')
  })

  it('/features も新ドメインの同一パスへ 301 で送る', async () => {
    const response = await legacy('/features')

    expect(response.status).toBe(301)
    expect(response.headers.get('Location')).toBe('https://befold.degino.com/features')
  })

  it('クエリ文字列は 301 先へ引き継ぐ（?ref= の参照元計測を落とさない）', async () => {
    const response = await legacy('/?ref=gh-pages')

    expect(response.headers.get('Location')).toBe('https://befold.degino.com/?ref=gh-pages')
  })

  it('staging の旧ホストは staging の新ドメインへ送る（本番へ送らない）', async () => {
    const response = await call('/', {}, undefined, LEGACY_STAGING)

    expect(response.status).toBe(301)
    expect(response.headers.get('Location')).toBe('https://staging.befold.degino.com/')
  })

  it('appcast は 301 ではなく 200 を返す（出荷済みアプリの更新経路）', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)
    await env.DIST.put('appcast-develop.xml', DEVELOP_XML)

    for (const path of ['/appcast.xml', '/appcast-develop.xml']) {
      const response = await legacy(path)

      expect(response.status).toBe(200)
      expect(response.headers.get('Location')).toBeNull()
    }
  })

  it('/dl/ は 301 ではなく 200 を返す（配信済み appcast の enclosure）', async () => {
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await legacy('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('DMG-BODY')
  })

  it('/download はリダイレクトせず source=lp を従来どおり記録する', async () => {
    await env.DIST.put(
      'releases/latest.json',
      JSON.stringify({ version: 'v1.2.3', file: 'befold-v1.2.3.dmg' }),
    )
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await legacy('/download')

    expect(response.status).toBe(200)
    const event = await latestEvent()
    expect(event?.kind).toBe('download')
    expect(event?.source).toBe('lp')
  })

  it('列挙外のパスはリダイレクトしない（肯定列挙であることの担保）', async () => {
    for (const path of ['/healthz', '/robots.txt', '/sitemap.xml']) {
      const response = await legacy(path)

      expect(response.status).toBe(200)
    }
  })

  it('新ドメインで来たリクエストはリダイレクトしない', async () => {
    const response = await call('/', {}, undefined, 'https://befold.degino.com')

    expect(response.status).toBe(200)
  })
})

/**
 * 移行期は旧ホストの LP から新ドメインへ遷移する。これは外部からの流入ではないので
 * 参照元の集計に混ぜてはならない（ADR 0007 の決定 6）。resolveReferrer の単体テスト
 * だけでは events.ts の結線漏れを検知できないため、実リクエスト経由でも確かめる。
 */
describe('新旧ホスト間の遷移の計測', () => {
  it('旧ホストからの遷移は参照元として記録しない', async () => {
    await call('/', { Referer: 'https://befold.tommy109.workers.dev/' }, undefined,
      'https://befold.degino.com')

    expect((await latestEvent())?.referrer).toBeNull()
  })

  it('外部サイトからの流入は従来どおり参照元として記録する', async () => {
    await call('/', { Referer: 'https://news.ycombinator.com/item?id=1' }, undefined,
      'https://befold.degino.com')

    expect((await latestEvent())?.referrer).toBe('https://news.ycombinator.com')
  })
})

/**
 * ダウンロード導線は配信ホストに依存しない（ADR 0007 の決定 6）。正規オリジンを
 * 固定すると staging の LP のボタンが本番を指し、staging で download 経路と
 * source:'lp' の計測を確かめられなくなる。
 */
describe('ダウンロード導線のホスト非依存性', () => {
  // 旧ホストの LP と /features は 301 で新ドメインへ送るため（決定 2）、HTML を
  // 描くのは新ドメインと staging。どちらで描いてもホスト名は現れない。
  it.each(['https://befold.degino.com', 'https://staging.befold.degino.com'])(
    '%s で開いても同一ホスト内の /download を指す',
    async (origin) => {
      for (const path of ['/', '/features']) {
        const body = await (await call(path, {}, undefined, origin)).text()

        expect(body).toContain('href="/download"')
        expect(body).not.toMatch(/href="https?:\/\/[^"]*\/download"/)
      }
    },
  )

  it('JSON-LD の downloadUrl はリクエスト origin から組む', async () => {
    const html = await (await call('/', {}, undefined, 'https://staging.befold.degino.com')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]

    expect(JSON.parse(json as string).downloadUrl).toBe('https://staging.befold.degino.com/download')
  })
})
