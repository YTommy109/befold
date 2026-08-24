import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import app from '../src/index'
import { pathFor, SITE_PAGES } from '../src/lib/pages'
import { pageSchema } from '../src/schema'
import { downloadHref } from '../src/views/shared'

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
  page: string | null
  browser_lang: string | null
  display_lang: string | null
  host: string | null
  fallback: string | null
  app_version: string | null
}

/**
 * `<body>` 以降だけを返す。
 *
 * 「相手言語が出ない」を HTML 全体で判定すると、head の
 * `<link rel="alternate" hreflang="en">` や `og:locale:alternate` に引っかかる。
 * これらは相手言語を指すのが正しい状態で、本文の言語混在とは別物。
 */
function bodyOf(html: string): string {
  const index = html.indexOf('<body>')
  return index === -1 ? html : html.slice(index)
}

/**
 * 最後に記録されたイベント。kind を渡すとその種別に絞る。
 *
 * 1 リクエストが 2 件記録することがある（R2 ミスの `github_fallback` と、その
 * 経路本来の download / update_check）。絞り込みを既定で入れて隠すのではなく、
 * どちらを見たいのかを呼び出し側に書かせる。
 */
async function latestEvent(kind?: string): Promise<EventRow | null> {
  const columns =
    'SELECT kind, version, channel, country, os, ua_summary, visitor_token, referrer, as_org,' +
    ' source, page, browser_lang, display_lang, host, fallback, app_version FROM events'
  const query = kind === undefined ? columns : `${columns} WHERE kind = ?`

  return await env.DB.prepare(`${query} ORDER BY id DESC LIMIT 1`)
    .bind(...(kind === undefined ? [] : [kind]))
    .first<EventRow>()
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
const RELEASES_LIST_URL = 'https://api.github.com/repos/YTommy109/befold/releases?per_page=100'
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
    expect(body).toContain(`href="${downloadHref('/')}"`)

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.country).toBe('JP')
    expect(event?.page).toBe('/')
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

    const event = await latestEvent('download')
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

    const event = await latestEvent('download')
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

    const event = await latestEvent('download')
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

    const event = await latestEvent('update_check')
    expect(event?.kind).toBe('update_check')
    expect(event?.channel).toBe('stable')
    expect(event?.ua_summary).toBe('Sparkle')
  })

  it('稼働中のアプリバージョンを app_version に記録する（TASK-491.1）', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    // Sparkle 2.9.4 が実際に送る形（実測、2026-08-16）。
    await call('/appcast.xml', { 'User-Agent': 'befold/1.13.2-dev.4 Sparkle/2.9.4' })

    const event = await latestEvent('update_check')
    expect(event?.app_version).toBe('1.13.2-dev.4')
    // version は download の対象タグ用。update_check では埋めない。
    expect(event?.version).toBeNull()
  })

  it('パースできない UA でも記録は成功し app_version は NULL になる', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    const response = await call('/appcast.xml', { 'User-Agent': 'curl/8.7.1' })

    expect(response.status).toBe(200)
    const event = await latestEvent('update_check')
    expect(event?.kind).toBe('update_check')
    expect(event?.app_version).toBeNull()
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
    expect(event?.visitor_token).toMatch(/^[0-9a-f]{64}$/u)
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

    const title = html.match(/<title>(.*?)<\/title>/u)?.[1]
    const description = html.match(/<meta name="description" content="(.*?)"\/>/u)?.[1]

    expect(title).toBeTruthy()
    expect(description).toBeTruthy()
    expect(html).toContain(`<meta property="og:title" content="${title}"/>`)
    expect(html).toContain(`<meta property="og:description" content="${description}"/>`)
  })
})

describe('対象 OS の明示', () => {
  it('ファーストビューのリード文で Mac 専用だと分かる（各言語の URL で）', async () => {
    const ja = (await (await call('/')).text()).match(
      /<section class="hero">([\s\S]*?)<\/section>/u,
    )?.[1]
    const en = (await (await call('/en')).text()).match(
      /<section class="hero">([\s\S]*?)<\/section>/u,
    )?.[1]

    expect(ja).toContain('Mac 専用')
    expect(en).toContain('Mac-only')
    // 言語ごとに URL が分かれた以上、片方の本文にもう片方の言語は出ない。
    expect(ja).not.toContain('Mac-only')
    expect(en).not.toContain('Mac 専用')
  })

  it('ダウンロードボタンの近辺で macOS 14 以降だと分かる', async () => {
    for (const [path, note] of [
      ['/', 'macOS 14 (Sonoma) 以降が必要です'],
      ['/en', 'Requires macOS 14 (Sonoma) or later'],
    ]) {
      const html = await (await call(path as string)).text()
      const hero = html.match(/<section class="hero">([\s\S]*?)<\/section>/u)?.[1] ?? ''

      expect(hero, path).toContain(note)
      // 注記はボタンより後ろに置き、クリック前に目に入るようにする。
      expect(hero.indexOf('btn-primary'), path).toBeLessThan(hero.indexOf('hero-note'))
    }
  })
})

describe('構造化データ (JSON-LD)', () => {
  it('SoftwareApplication として macOS 専用・ダウンロード先を示す', async () => {
    const html = await (await call('/')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

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
    const description = html.match(/<meta name="description" content="(.*?)"\/>/u)?.[1]
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

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
    // SITE_PAGES の全バリアントが載る。ここが表とずれると、追加した言語ページが
    // クロールされないまま気づけない。
    for (const entry of SITE_PAGES) {
      expect(body, entry.path).toContain(`<loc>https://befold.example${entry.path}</loc>`)
    }
    expect(body.match(/<loc>/gu)).toHaveLength(SITE_PAGES.length)
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
    expect(body).toContain('キーボードショートカット')
    expect(body).toContain('よくある質問')
  })

  it('英語版は /en/features にあり、日本語の本文は出ない', async () => {
    const response = await call('/en/features')

    expect(response.status).toBe(200)
    const body = bodyOf(await response.text())
    expect(body).toContain('Supported File Types')
    expect(body).toContain('Keyboard Shortcuts')
    expect(body).toContain('Frequently Asked Questions')
    expect(body).not.toContain('対応ファイルタイプ')
  })

  it('日本語版の本文に英語の文面は出ない', async () => {
    // head は判定に含めない。hreflang / og:locale:alternate が相手言語を指すのは
    // 正しい状態で、本文の混在とは別物。
    const body = bodyOf(await (await call('/features')).text())

    expect(body).not.toContain('Supported File Types')
    expect(body).not.toContain('Keyboard Shortcuts')
    // hidden で隠す旧方式が復活していないことも同時に見る。
    expect(body).not.toMatch(/lang="en"[^>]*hidden/u)
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
    const json = body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

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

  it('page=/features の visit として記録する', async () => {
    await call('/features')

    const event = await latestEvent()
    expect(event?.kind).toBe('visit')
    expect(event?.page).toBe('/features')
  })

  it('キャッシュに載せない（載ると Worker を通らず計上できない）', async () => {
    const response = await call('/features')

    // ヘッダを外すだけでは足りない。Cache-Control も Expires も無い 200 応答は
    // ブラウザのヒューリスティックキャッシュに載り得るため、明示して固定する。
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('ブラウザ言語設定の記録', () => {
  it('Accept-Language の第一タグを ja / en / other に丸めて記録する', async () => {
    const cases: [string, string][] = [
      ['ja,en-US;q=0.9', 'ja'],
      ['en-US,en;q=0.9', 'en'],
      ['fr-FR,fr;q=0.9', 'other'],
    ]

    for (const [header, expected] of cases) {
      await call('/', { 'Accept-Language': header })
      expect((await latestEvent())?.browser_lang, header).toBe(expected)
    }
  })

  it('Accept-Language が無いリクエストでは NULL になる', async () => {
    // Sparkle の自動更新はこのヘッダを送らない。記録処理自体は止めない。
    await call('/dl/v1.0.0/befold-1.0.0.dmg', { 'Accept-Language': '' })

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.browser_lang).toBeNull()
  })

  it('visit 以外の kind では page が NULL になる', async () => {
    await call('/dl/v1.0.0/befold-1.0.0.dmg')

    const event = await latestEvent('download')
    expect(event?.kind).toBe('download')
    expect(event?.page).toBeNull()
  })
})

/**
 * ヘッダーの共通ナビ（TASK-542）。全ページ・両言語で同じ動線が出ることを、
 * 実際のレスポンス HTML で確かめる。
 */
describe('ヘッダーのナビゲーションバー', () => {
  // `/releases` は意図してナビに出さない（`FIXED_PAGES` の `nav: false`）。
  const NAV_PAGES = ['/', '/features', '/usecases'] as const

  for (const lang of ['ja', 'en'] as const) {
    const pages = SITE_PAGES.filter((entry) => entry.lang === lang)

    for (const entry of pages) {
      it(`${entry.path} のヘッダーに ${lang} の全ナビ項目が出る`, async () => {
        const body = await (await call(entry.path)).text()
        const nav = body.slice(body.indexOf('<nav class="site-nav"'))

        for (const page of NAV_PAGES) {
          expect(nav).toContain(`href="${pathFor(page, lang)}"`)
        }
      })
    }
  }

  it('過去のバージョンはナビに出さない', async () => {
    const body = await (await call('/')).text()
    const nav = body.slice(body.indexOf('<nav class="site-nav"'), body.indexOf('</nav>'))

    expect(nav).not.toContain('href="/releases"')
  })

  it('固定ページでは現在地が aria-current で分かる', async () => {
    const body = await (await call('/features')).text()

    expect(body).toContain(`<a class="site-nav-link" href="/features" aria-current="page">`)
  })

  it('英語ページのナビは /en 配下を指す', async () => {
    const body = await (await call('/en')).text()
    const nav = body.slice(body.indexOf('<nav class="site-nav"'), body.indexOf('</nav>'))

    expect(nav).toContain('href="/en/usecases"')
    expect(nav).not.toContain('href="/usecases"')
  })

  it('トップページから事例一覧へ 1 クリックで到達できる', async () => {
    const body = await (await call('/')).text()

    expect(body).toContain('href="/usecases"')
  })
})

describe('LP から詳細ページへの導線', () => {
  it('LP に /features への内部リンクがある', async () => {
    const body = await (await call('/')).text()

    expect(body).toContain('href="/features"')
  })

  // ナビから外した分、過去バージョンへの動線は LP のインストール章だけが持つ。
  it('LP のインストール章から過去バージョンへ辿れる', async () => {
    const body = await (await call('/')).text()
    const install = body.slice(body.indexOf('<section class="install">'))

    expect(install).toContain('href="/releases"')
    expect(install).toContain('過去バージョンが必要な方はこちら')
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

  it('SITE_PAGES の全ページを新ドメインの同一パスへ 301 で送る', async () => {
    // リダイレクト対象は SITE_PAGES からの導出（lib/hosts.ts）。言語ページを
    // 足したのに旧ホストの列挙だけ取り残される、という形を潰すためのループ。
    for (const entry of SITE_PAGES) {
      const response = await legacy(entry.path)

      expect(response.status, entry.path).toBe(301)
      expect(response.headers.get('Location'), entry.path).toBe(
        `https://befold.degino.com${entry.path}`,
      )
    }
  })

  it('301 を legacy_redirect として記録する（visit にはしない）', async () => {
    // visit として記録すると、301 を追った先の正規ホストでも visit が記録され、
    // ページアクセス数が二重に数えられる。
    const response = await legacy('/')

    expect(response.status).toBe(301)
    const event = await latestEvent()
    expect(event?.kind).toBe('legacy_redirect')
    expect(event?.host).toBe('befold.tommy109.workers.dev')
    expect(event?.page).toBeNull()

    const visits = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM events WHERE kind = 'visit'",
    ).first<{ count: number }>()
    expect(visits?.count).toBe(0)
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
    const event = await latestEvent('download')
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
    await call(
      '/',
      { Referer: 'https://befold.tommy109.workers.dev/' },
      undefined,
      'https://befold.degino.com',
    )

    expect((await latestEvent())?.referrer).toBeNull()
  })

  it('外部サイトからの流入は従来どおり参照元として記録する', async () => {
    await call(
      '/',
      { Referer: 'https://news.ycombinator.com/item?id=1' },
      undefined,
      'https://befold.degino.com',
    )

    expect((await latestEvent())?.referrer).toBe('https://news.ycombinator.com')
  })
})

/**
 * ダウンロード導線は配信ホストに依存しない（ADR 0007 の決定 6）。正規オリジンを
 * 固定すると staging の LP のボタンが本番を指し、staging で download 経路と
 * source:'lp' の計測を確かめられなくなる。
 */
/**
 * ダウンロードが始まった面を `?ref=` で記録する（TASK-549）。
 *
 * download イベントの referrer は、サイト内リンク経由だと Referer が自ホストに
 * なるため `?ref=` が無ければ null になり、集計の `WHERE referrer IS NOT NULL` で
 * 行ごと消える。「素の /download でリンクを書く」形へ戻ると計測が静かに失われる
 * ので、リンク側と記録側の両方をここで固定する。
 */
describe('ダウンロード導線の ?ref=', () => {
  it.each([
    ['/', '/'],
    ['/features', '/features'],
    ['/usecases/medical-expenses', '/usecases/medical-expenses'],
  ] as const)('%s のダウンロードリンクに ?ref= が付く', async (path, page) => {
    const body = await (await call(path)).text()

    expect(body).toContain(`href="${downloadHref(page)}"`)
  })

  /**
   * `downloadHref()` を迂回して素の `/download` を書いた形の検出。href の直後が
   * `"` で終わるものだけを見る（`?ref=` 付きは `?` が続くので一致しない）。
   */
  it.each(['/', '/features', '/usecases/medical-expenses', '/en', '/en/features'])(
    '%s に素の href="/download" が残っていない',
    async (path) => {
      const body = await (await call(path)).text()

      expect(body).not.toContain('href="/download"')
    },
  )

  it('?ref= の値がそのまま download イベントの referrer になる', async () => {
    await call(downloadHref('/usecases/medical-expenses'))

    const event = await latestEvent('download')
    expect(event?.source).toBe('lp')
    expect(event?.referrer).toBe('usecases-medical-expenses')
  })

  /** ref を付けずに直接叩いた場合は従来どおり（自ホスト Referer は null）。 */
  it('?ref= が無ければ referrer は記録されない', async () => {
    await call('/download')

    const event = await latestEvent('download')
    expect(event?.source).toBe('lp')
    expect(event?.referrer).toBeNull()
  })
})

describe('ダウンロード導線のホスト非依存性', () => {
  // 旧ホストの LP と /features は 301 で新ドメインへ送るため（決定 2）、HTML を
  // 描くのは新ドメインと staging。どちらで描いてもホスト名は現れない。
  it.each(['https://befold.degino.com', 'https://staging.befold.degino.com'])(
    '%s で開いても同一ホスト内の /download を指す',
    async (origin) => {
      for (const page of ['/', '/features'] as const) {
        const body = await (await call(page, {}, undefined, origin)).text()

        expect(body).toContain(`href="${downloadHref(page)}"`)
        expect(body).not.toMatch(/href="https?:\/\/[^"]*\/download/u)
      }
    },
  )

  it('JSON-LD の downloadUrl はリクエスト origin から組む', async () => {
    const html = await (await call('/', {}, undefined, 'https://staging.befold.degino.com')).text()
    const json = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/u)?.[1]

    expect(JSON.parse(json as string).downloadUrl).toBe(
      'https://staging.befold.degino.com/download',
    )
  })
})

describe('GET /releases（過去バージョン一覧）', () => {
  /** GitHub API の応答の形をそのまま真似る。除外条件を実データの形で確かめる。 */
  const RELEASES_JSON = [
    {
      tag_name: 'v1.13.3-dev.1',
      published_at: '2026-08-16T13:43:02Z',
      prerelease: true,
      assets: [{ name: 'befold-v1.13.3-dev.1.dmg' }],
    },
    {
      tag_name: 'v1.13.2',
      published_at: '2026-08-16T10:16:56Z',
      prerelease: false,
      assets: [{ name: 'befold-v1.13.2.dmg' }],
    },
    // 版を表さない固定タグ。prerelease ではないので、フラグだけでは弾けない。
    {
      tag_name: 'appcast',
      published_at: '2026-08-16T10:20:00Z',
      prerelease: false,
      assets: [{ name: 'appcast.xml' }],
    },
    // DMG が無いリリース。行にしてもダウンロードできない。
    {
      tag_name: 'v1.0.0',
      published_at: '2026-01-01T00:00:00Z',
      prerelease: false,
      assets: [],
    },
    // 旧名のアセット。現在の命名規約（befold-<tag>.dmg）では導出できない。
    {
      tag_name: 'v1.3.3',
      published_at: '2026-05-01T00:00:00Z',
      prerelease: false,
      assets: [{ name: 'mmdview-v1.3.3.dmg' }],
    },
  ]

  function mockReleases(body: unknown, status = 200): void {
    mockUpstream({ [RELEASES_LIST_URL]: new Response(JSON.stringify(body), { status }) })
  }

  it('stable だけを表に出し、公開日・リリースノート・ダウンロードを並べる', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).toContain('v1.13.2')
    expect(html).toContain('2026-08-16')
    expect(html).toContain('https://github.com/YTommy109/befold/releases/tag/v1.13.2')
    expect(html).toContain('/releases/v1.13.2/befold-v1.13.2.dmg')
    // 旧名のアセットも、そのままのファイル名でリンクする。
    expect(html).toContain('/releases/v1.3.3/mmdview-v1.3.3.dmg')
  })

  it('develop・版でないタグ・DMG 無しは一覧に出さない', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).not.toContain('dev.1')
    expect(html).not.toContain('appcast')
    expect(html).not.toContain('v1.0.0')
  })

  it('visit を /releases として記録する', async () => {
    mockReleases(RELEASES_JSON)

    await call('/releases')

    const event = await latestEvent('visit')
    expect(event?.page).toBe('/releases')
    expect(event?.display_lang).toBe('ja')
  })

  it('取得に失敗しても 200 で、取得できなかったことを伝える', async () => {
    mockReleases({ message: 'rate limit' }, 403)

    const response = await call('/releases')
    const html = bodyOf(await response.text())

    expect(response.status).toBe(200)
    expect(html).toContain('取得できませんでした')
    // 行き止まりにせず GitHub の一覧へ逃がす。
    expect(html).toContain('https://github.com/YTommy109/befold/releases')
  })

  it('取得できて 0 件のときは「取得できなかった」とは言わない', async () => {
    mockReleases([])

    const html = bodyOf(await (await call('/releases')).text())

    expect(html).toContain('まだありません')
    expect(html).not.toContain('取得できませんでした')
  })

  it('英語版は英語で出す', async () => {
    mockReleases(RELEASES_JSON)

    const html = bodyOf(await (await call('/en/releases')).text())

    expect(html).toContain('Previous versions')
    expect(html).not.toContain('過去のバージョン')
  })
})

describe('GET /releases/:tag/:file（旧バージョンの配信）', () => {
  it('R2 にあれば DMG を返し source=archive を記録する', async () => {
    await env.DIST.put('releases/v1.12.0/befold-v1.12.0.dmg', 'OLD-DMG')

    const response = await call('/releases/v1.12.0/befold-v1.12.0.dmg')

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('OLD-DMG')

    const event = await latestEvent('download')
    expect(event?.source).toBe('archive')
    expect(event?.version).toBe('v1.12.0')
    expect(event?.channel).toBe('stable')
  })

  it('R2 に無ければ GitHub へ 302 し、fallback は dmg と分けて記録する', async () => {
    const response = await call('/releases/v1.3.3/mmdview-v1.3.3.dmg')

    expect(response.status).toBe(302)
    expect(response.headers.get('location')).toBe(
      'https://github.com/YTommy109/befold/releases/download/v1.3.3/mmdview-v1.3.3.dmg',
    )

    // 旧版が R2 に無いのは配置漏れではない。`dmg`（配布の穴）に混ぜない。
    const fallback = await latestEvent('github_fallback')
    expect(fallback?.fallback).toBe('archive-dmg')

    const download = await latestEvent('download')
    expect(download?.source).toBe('archive')
    expect(download?.version).toBe('v1.3.3')
  })

  it('develop タグは配らない（一覧に出していないものを URL 直打ちで取らせない）', async () => {
    await env.DIST.put('releases/v1.13.3-dev.1/befold-v1.13.3-dev.1.dmg', 'DEV-DMG')

    const response = await call('/releases/v1.13.3-dev.1/befold-v1.13.3-dev.1.dmg')

    expect(response.status).toBe(404)
    expect(await latestEvent('download')).toBeNull()
  })

  it('キーを組めない形のファイル名は 404 にする', async () => {
    const response = await call('/releases/v1.12.0/..%2Flatest.json')

    expect(response.status).toBe(404)
    expect(await latestEvent('download')).toBeNull()
  })
})

describe('言語ごとの URL（SITE_PAGES からの導出）', () => {
  // /releases は GitHub API を読む。差し替えないとテストが外部の可用性と
  // レート制限に依存する（応答の中身はここでは見ないので、縮退させておく）。
  beforeEach(() => {
    mockUpstream({ [RELEASES_LIST_URL]: new Response('{}', { status: 503 }) })
  })

  it('表に載っている全ページが 200 を返し、html lang が表と一致する', async () => {
    for (const entry of SITE_PAGES) {
      const response = await call(entry.path)

      expect(response.status, entry.path).toBe(200)
      expect(await response.text(), entry.path).toContain(`<html lang="${entry.lang}">`)
    }
  })

  it('各ページの hreflang が自己参照を含む全バリアントを列挙する', async () => {
    // 自己参照を落とすと検索エンジンから見た対応関係が成立しない。省きやすい
    // ところなので、集合の一致で固定する。
    for (const entry of SITE_PAGES) {
      const html = await (await call(entry.path)).text()
      const found = [...html.matchAll(/<link rel="alternate" hreflang="(\w+)" href="([^"]+)"\/>/gu)]
      const expected = SITE_PAGES.filter((variant) => variant.page === entry.page)

      expect(found.map((match) => match[2]).toSorted(), entry.path).toEqual(
        expected.map((variant) => `https://befold.example${variant.path}`).toSorted(),
      )
      expect(found.map((match) => match[1]).toSorted(), entry.path).toEqual(
        expected.map((variant) => variant.lang).toSorted(),
      )
    }
  })

  it('各ページの canonical が自分自身を指す', async () => {
    for (const entry of SITE_PAGES) {
      const html = await (await call(entry.path)).text()

      expect(html, entry.path).toContain(
        `<link rel="canonical" href="https://befold.example${entry.path}"/>`,
      )
    }
  })

  it('言語ごとに og:locale と og:locale:alternate が入れ替わる', async () => {
    const ja = await (await call('/')).text()
    const en = await (await call('/en')).text()

    expect(ja).toContain('<meta property="og:locale" content="ja_JP"/>')
    expect(ja).toContain('<meta property="og:locale:alternate" content="en_US"/>')
    expect(en).toContain('<meta property="og:locale" content="en_US"/>')
    expect(en).toContain('<meta property="og:locale:alternate" content="ja_JP"/>')
  })

  it('表示した言語が display_lang として記録される', async () => {
    for (const entry of SITE_PAGES) {
      await call(entry.path)
      const event = await latestEvent()

      expect(event?.kind, entry.path).toBe('visit')
      expect(event?.page, entry.path).toBe(entry.page)
      expect(event?.display_lang, entry.path).toBe(entry.lang)
    }
  })

  it('ブラウザ言語設定と表示言語は別々に記録される', async () => {
    // 英語設定のブラウザが日本語ページを見ている、という取りこぼしを測れること。
    // これが分からないと「英語を求めて来た人が英語ページへ辿り着けたか」が出ない。
    await call('/', { 'Accept-Language': 'en-US,en;q=0.9' })

    const event = await latestEvent()
    expect(event?.browser_lang).toBe('en')
    expect(event?.display_lang).toBe('ja')
  })

  it('全 4 ページがキャッシュに載らない', async () => {
    // 1 本でも載ると、そのページの計測だけが環境依存で欠けて日英比率が歪む。
    for (const entry of SITE_PAGES) {
      const response = await call(entry.path)

      expect(response.headers.get('Cache-Control'), entry.path).toBe('no-store')
    }
  })

  it('言語切替リンクが相手言語のページを指し、現在地に aria-current が付く', async () => {
    const html = await (await call('/features')).text()

    expect(html).toContain('href="/en/features"')
    expect(html).toMatch(/<a[^>]*class="lang-btn"[^>]*href="\/features"[^>]*aria-current="page"/u)
  })

  it('SITE_PAGES の page がすべて pageSchema の列挙に含まれる', () => {
    // pageSchema は z.enum のリテラルタプルを保つため手書きのまま残してある
    // （導出すると Page 型が string へ広がり、EventAttributes と METRIC_FILTERS の
    // 型安全が失われる）。その代わり両者のずれをここで検知する。
    for (const entry of SITE_PAGES) {
      expect(() => pageSchema.parse(entry.page), entry.path).not.toThrow()
    }
  })

  it('存在しない言語パスは 200 を返さない', async () => {
    // /en/download は作らない。/download を単一に保たないと LP 由来の
    // ダウンロード計測（source:'lp'）が言語ごとに割れる。
    for (const path of ['/en/download', '/ja', '/ja/features']) {
      expect((await call(path)).status, path).not.toBe(200)
    }
  })
})

/**
 * リクエスト先ホストと、R2 ミスによる GitHub フォールバックの記録。
 *
 * ADR 0007 の「旧ホストと GitHub 経路を止めてよいか」の判断材料になる
 * （旧ホストの appcast を叩くクライアントがゼロか / R2 ミスがゼロか）。
 */
describe('リクエスト先ホストと GitHub フォールバックの記録', () => {
  it('既知のホストはそのまま、それ以外は other として記録する', async () => {
    await call('/', {}, undefined, 'https://befold.degino.com')
    expect((await latestEvent())?.host).toBe('befold.degino.com')

    await call('/', {}, undefined, 'https://staging.befold.degino.com')
    expect((await latestEvent())?.host).toBe('staging.befold.degino.com')

    // 既定オリジンは既知ホストではない（preview URL や wrangler dev に相当）。
    // 生の Host をそのまま入れるとカーディナリティが発散するため 1 つに丸める。
    await call('/')
    expect((await latestEvent())?.host).toBe('other')
  })

  it('旧ホストの appcast はリダイレクトされず、旧ホストのまま記録される', async () => {
    // ここが記録できないと ADR 0007 の停止条件を永久に判定できない。
    await env.DIST.put('appcast.xml', APPCAST_XML)

    const response = await call(
      '/appcast.xml',
      { 'User-Agent': 'befold/1.2.3 Sparkle/2.6.4' },
      undefined,
      'https://befold.tommy109.workers.dev',
    )

    expect(response.status).toBe(200)
    const event = await latestEvent('update_check')
    expect(event?.host).toBe('befold.tommy109.workers.dev')
  })

  it('R2 に appcast が無ければ github_fallback を appcast として記録する', async () => {
    mockUpstream({ [APPCAST_URL]: new Response(APPCAST_XML) })

    await call('/appcast.xml')

    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('appcast')
    expect(event?.channel).toBe('stable')
  })

  it('R2 に appcast があればフォールバックは記録されない', async () => {
    await env.DIST.put('appcast.xml', APPCAST_XML)

    await call('/appcast.xml')

    expect(await latestEvent('github_fallback')).toBeNull()
  })

  it('R2 に DMG が無ければ github_fallback を dmg として記録する', async () => {
    const response = await call('/dl/v1.2.3/befold-v1.2.3.dmg')

    expect(response.status).toBe(302)
    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('dmg')
    expect(event?.version).toBe('v1.2.3')
  })

  it('不正なタグ・ファイル名は dmg ではなく dmg-invalid として記録する', async () => {
    // 検証で弾いたリクエスト（配布対象でない）を R2 の欠落と混ぜない。混ぜると
    // 「配布の穴」を数えているはずの dmg がパス探索でいくらでも増える。
    for (const path of ['/dl/latest/befold-v1.2.3.dmg', '/dl/v1.2.3/latest.json']) {
      const response = await call(path)

      expect(response.status).toBe(302)
      expect((await latestEvent('github_fallback'))?.fallback).toBe('dmg-invalid')
    }
  })

  it('R2 に最新ポインタが無ければ github_fallback を release-api として記録する', async () => {
    mockUpstream({
      [LATEST_RELEASE_URL]: Response.json({
        tag_name: 'v1.2.3',
        assets: [
          {
            name: 'befold-v1.2.3.dmg',
            browser_download_url: 'https://github.com/x/y/releases/download/v1.2.3/a.dmg',
          },
        ],
      }),
    })

    await call('/download')

    const event = await latestEvent('github_fallback')
    expect(event?.fallback).toBe('release-api')
  })

  it('R2 から配れたときはフォールバックを記録しない', async () => {
    await env.DIST.put('releases/latest.json', '{"version":"v1.2.3","file":"befold-v1.2.3.dmg"}')
    await env.DIST.put('releases/v1.2.3/befold-v1.2.3.dmg', 'DMG-BODY')

    const response = await call('/download')

    expect(response.status).toBe(200)
    expect(await latestEvent('github_fallback')).toBeNull()
  })
})

describe('404 ページ', () => {
  /** events の行数。404 が指標へ混ざっていないことは kind ではなく総数で見る。 */
  async function eventCount(): Promise<number> {
    const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM events').first<{ n: number }>()
    return row?.n ?? 0
  }

  it('ルートにも静的アセットにも当たらないパスは LP の意匠の 404 を返す', async () => {
    const response = await call('/en/download')

    expect(response.status).toBe(404)
    expect(response.headers.get('Content-Type')).toContain('text/html')
    const body = await response.text()
    // LP と同じ style.css を読み込み、同じ hero / btn-primary の意匠を使う。
    expect(body).toContain('<link rel="stylesheet" href="/style.css"/>')
    expect(body).toContain('class="hero"')
    expect(body).toContain('404')
  })

  it('日本語ページと英語ページの両方への導線がある', async () => {
    const body = await (await call('/nope')).text()

    // 宛先は SITE_PAGES から導出する。パスを変えたときにテストだけが取り残されないように。
    for (const lang of ['ja', 'en'] as const) {
      expect(bodyOf(body)).toContain(`href="${pathFor('/', lang)}"`)
    }
  })

  it('noindex を付け canonical は出さない', async () => {
    const body = await (await call('/nope')).text()

    expect(body).toContain('<meta name="robots" content="noindex"/>')
    // SITE_PAGES に無いパスなので、正規 URL も言語版の対応関係も主張しない。
    expect(body).not.toContain('rel="canonical"')
    expect(body).not.toContain('hreflang="ja" href=')
  })

  it('events に記録しない（LP の指標に混ざらない）', async () => {
    expect(await eventCount()).toBe(0)

    await call('/nope')
    await call('/en/nope')

    expect(await eventCount()).toBe(0)
  })

  it('実在する静的アセットは 404 に差し替えない', async () => {
    const response = await call('/style.css')

    expect(response.status).toBe(200)
    expect(await response.text()).toContain('.btn-primary')
  })

  it('キャッシュに載せない', async () => {
    const response = await call('/nope')

    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('HEAD 要求の計測', () => {
  /** 本文を取らない HEAD。Hono は GET のハンドラへ流すため、記録側で分ける必要がある。 */
  async function head(path: string): Promise<Response> {
    const request = new Request(`${DEFAULT_ORIGIN}${path}`, {
      method: 'HEAD',
      headers: { 'User-Agent': UA, 'CF-Connecting-IP': IP, 'CF-IPCountry': 'JP' },
      redirect: 'manual',
    })
    const ctx = createExecutionContext()
    const response = await app.fetch(request, env, ctx)
    await waitOnExecutionContext(ctx)
    return response
  }

  async function eventCount(): Promise<number> {
    const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM events').first<{ n: number }>()
    return row?.n ?? 0
  }

  // 3 経路すべてを並べる。1 つだけ直すと、次にダウンロード経路を足したときに
  // 同じ穴が復活する（記録側の絞り込み点で弾いていることをここで固定する）。
  it.each([
    ['/download', 'lp'],
    ['/dl/v1.12.0/befold-v1.12.0.dmg', 'sparkle'],
    ['/releases/v1.12.0/befold-v1.12.0.dmg', 'archive'],
  ])('%s への HEAD は download を記録しない', async (path) => {
    await env.DIST.put('releases/v1.12.0/befold-v1.12.0.dmg', 'OLD-DMG')
    await env.DIST.put('dl/v1.12.0/befold-v1.12.0.dmg', 'DMG')

    await head(path)

    expect(await latestEvent('download')).toBeNull()
  })

  it('LP への HEAD はページアクセスに数えない', async () => {
    await head('/')

    expect(await eventCount()).toBe(0)
  })

  it('GET なら同じ経路で記録される（HEAD の除外が記録全体を止めていない）', async () => {
    await call('/download')

    expect(await latestEvent('download')).not.toBeNull()
  })
})
